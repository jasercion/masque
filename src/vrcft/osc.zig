const std = @import("std");
const expressions = @import("expressions.zig");
const Expression = expressions.Expression;
const UnifiedTrackingData = expressions.UnifiedTrackingData;

/// OSC Value types supported in VRCFT communication
pub const OscValue = union(enum) {
    float: f32,
    int: i32,
    bool_val: bool,
    string: []const u8,

    pub fn typeTag(self: OscValue) u8 {
        return switch (self) {
            .float => 'f',
            .int => 'i',
            .bool_val => |b| if (b) @as(u8, 'T') else @as(u8, 'F'),
            .string => 's',
        };
    }
};

/// OSC Message builder and serializer.
pub const OscMessage = struct {
    address: []const u8,
    value: OscValue,

    pub fn init(address: []const u8, value: OscValue) OscMessage {
        return .{
            .address = address,
            .value = value,
        };
    }

    /// Calculates required buffer size for the encoded OSC message with 4-byte alignment padding.
    pub fn encodedSize(self: OscMessage) usize {
        const addr_len = self.address.len + 1; // null terminator
        const addr_padded = (addr_len + 3) & ~@as(usize, 3);

        var type_tag_len: usize = 0;
        var args_len: usize = 0;

        switch (self.value) {
            .float, .int => {
                type_tag_len = 2 + 1; // ",f\0" or ",i\0"
                args_len = 4;
            },
            .bool_val => {
                type_tag_len = 2 + 1; // ",T\0" or ",F\0"
                args_len = 0;
            },
            .string => |s| {
                type_tag_len = 2 + 1; // ",s\0"
                const s_len = s.len + 1;
                args_len = (s_len + 3) & ~@as(usize, 3);
            },
        }

        const type_tag_padded = (type_tag_len + 3) & ~@as(usize, 3);
        return addr_padded + type_tag_padded + args_len;
    }

    /// Serializes the OSC message into the destination buffer.
    pub fn encode(self: OscMessage, dest: []u8) !usize {
        const required = self.encodedSize();
        if (dest.len < required) return error.BufferTooSmall;

        var cursor: usize = 0;

        // 1. Write address
        @memcpy(dest[cursor .. cursor + self.address.len], self.address);
        cursor += self.address.len;
        dest[cursor] = 0;
        cursor += 1;
        while (cursor % 4 != 0) : (cursor += 1) {
            dest[cursor] = 0;
        }

        // 2. Write Type Tag String
        dest[cursor] = ',';
        cursor += 1;
        dest[cursor] = self.value.typeTag();
        cursor += 1;
        dest[cursor] = 0;
        cursor += 1;
        while (cursor % 4 != 0) : (cursor += 1) {
            dest[cursor] = 0;
        }

        // 3. Write Argument Payload
        switch (self.value) {
            .float => |f| {
                const bits = @as(u32, @bitCast(f));
                const big = std.mem.nativeToBig(u32, bits);
                const bytes: [4]u8 = @bitCast(big);
                @memcpy(dest[cursor .. cursor + 4], &bytes);
                cursor += 4;
            },
            .int => |i| {
                const bits = @as(u32, @bitCast(i));
                const big = std.mem.nativeToBig(u32, bits);
                const bytes: [4]u8 = @bitCast(big);
                @memcpy(dest[cursor .. cursor + 4], &bytes);
                cursor += 4;
            },
            .bool_val => {
                // 'T' and 'F' type tags do not take argument payload bytes in OSC 1.1
            },
            .string => |s| {
                @memcpy(dest[cursor .. cursor + s.len], s);
                cursor += s.len;
                dest[cursor] = 0;
                cursor += 1;
                while (cursor % 4 != 0) : (cursor += 1) {
                    dest[cursor] = 0;
                }
            },
        }

        return cursor;
    }
};

/// OSC Bundle builder to transmit multiple OSC messages in a single atomic UDP datagram.
pub const OscBundle = struct {
    timetag: u64 = 1, // 1 = immediately
    messages: std.ArrayListUnmanaged(OscMessage) = .empty,

    pub fn init() OscBundle {
        return .{};
    }

    pub fn deinit(self: *OscBundle, allocator: std.mem.Allocator) void {
        self.messages.deinit(allocator);
    }

    pub fn addMessage(self: *OscBundle, allocator: std.mem.Allocator, msg: OscMessage) !void {
        try self.messages.append(allocator, msg);
    }

    pub fn encodedSize(self: *const OscBundle) usize {
        // "#bundle\0" (8 bytes) + timetag (8 bytes) = 16 bytes
        var total: usize = 16;
        for (self.messages.items) |msg| {
            total += 4 + msg.encodedSize(); // 4-byte size prefix + message size
        }
        return total;
    }

    pub fn encode(self: *const OscBundle, dest: []u8) !usize {
        const required = self.encodedSize();
        if (dest.len < required) return error.BufferTooSmall;

        var cursor: usize = 0;

        // 1. Bundle header "#bundle\0"
        const header = "#bundle\x00";
        @memcpy(dest[cursor .. cursor + 8], header);
        cursor += 8;

        // 2. Timetag (8 bytes, big-endian)
        const tt_big = std.mem.nativeToBig(u64, self.timetag);
        const tt_bytes: [8]u8 = @bitCast(tt_big);
        @memcpy(dest[cursor .. cursor + 8], &tt_bytes);
        cursor += 8;

        // 3. Elements
        for (self.messages.items) |msg| {
            const msg_size = msg.encodedSize();
            const size_big = std.mem.nativeToBig(u32, @intCast(msg_size));
            const size_bytes: [4]u8 = @bitCast(size_big);
            @memcpy(dest[cursor .. cursor + 4], &size_bytes);
            cursor += 4;

            const written = try msg.encode(dest[cursor .. cursor + msg_size]);
            cursor += written;
        }

        return cursor;
    }
};

/// VRCFT Parameter Output Mode
pub const OutputMode = enum {
    float_parameters,
    binary_parameters,
};

/// Formatting options for VRCFT OSC addresses
pub const OscAddressConfig = struct {
    base_prefix: []const u8 = "/avatar/parameters",
    v2_subpath: []const u8 = "v2",
    custom_prefix: ?[]const u8 = null,

    /// Formats parameter address into a fixed-size buffer.
    pub fn formatAddress(self: OscAddressConfig, buf: []u8, param_name: []const u8) ![]const u8 {
        if (self.custom_prefix) |cp| {
            return try std.fmt.bufPrint(buf, "{s}/{s}/{s}/{s}", .{
                self.base_prefix,
                cp,
                self.v2_subpath,
                param_name,
            });
        } else if (self.v2_subpath.len > 0) {
            return try std.fmt.bufPrint(buf, "{s}/{s}/{s}", .{
                self.base_prefix,
                self.v2_subpath,
                param_name,
            });
        } else {
            return try std.fmt.bufPrint(buf, "{s}/{s}", .{
                self.base_prefix,
                param_name,
            });
        }
    }
};

/// Converter from UnifiedTrackingData to standard VRCFT OSC Messages / Bundles.
pub const VrcftOscEncoder = struct {
    config: OscAddressConfig = .{},
    output_mode: OutputMode = .float_parameters,
    binary_bits: u4 = 4, // standard 4-bit, 8-bit, or custom quantization

    pub fn encodeTrackingDataToBundle(
        self: *const VrcftOscEncoder,
        allocator: std.mem.Allocator,
        data: *const UnifiedTrackingData,
        bundle: *OscBundle,
    ) !void {
        var addr_buf: [256]u8 = undefined;

        inline for (@typeInfo(Expression).@"enum".field_names) |name_str| {
            const expr = @field(Expression, name_str);
            const val = data.get(expr);

            // Skip zero or near-zero noise if desired, but for full fidelity send all active params
            const formatted_addr = try self.config.formatAddress(&addr_buf, name_str);
            const addr_copy = try allocator.dupe(u8, formatted_addr);

            switch (self.output_mode) {
                .float_parameters => {
                    try bundle.addMessage(allocator, OscMessage.init(addr_copy, .{ .float = val }));
                },
                .binary_parameters => {
                    // Encode Binary parameter bits according to docs.vrcft.io
                    const max_val: u32 = (@as(u32, 1) << self.binary_bits) - 1;
                    const quantized: u32 = @intFromFloat(std.math.round(val * @as(f32, @floatFromInt(max_val))));

                    // Emit bit messages: e.g. <Name>1, <Name>2, <Name>4, etc.
                    var bit_idx: u4 = 0;
                    while (bit_idx < self.binary_bits) : (bit_idx += 1) {
                        const bit_mask = @as(u32, 1) << bit_idx;
                        const is_set = (quantized & bit_mask) != 0;
                        var bit_name_buf: [256]u8 = undefined;
                        const bit_param_name = try std.fmt.bufPrint(&bit_name_buf, "{s}{d}", .{ name_str, bit_mask });
                        const bit_addr = try self.config.formatAddress(&addr_buf, bit_param_name);
                        const bit_addr_copy = try allocator.dupe(u8, bit_addr);
                        try bundle.addMessage(allocator, OscMessage.init(bit_addr_copy, .{ .bool_val = is_set }));
                    }
                },
            }
        }
    }
};

test "osc message encoding float" {
    const msg = OscMessage.init("/avatar/parameters/v2/JawOpen", .{ .float = 0.85 });
    var buf: [128]u8 = undefined;
    const len = try msg.encode(&buf);

    try std.testing.expect(len % 4 == 0);
    try std.testing.expectEqualStrings("/avatar/parameters/v2/JawOpen", std.mem.sliceTo(buf[0..], 0));

    // Type tag starts after padded address
    const addr_padded = (msg.address.len + 1 + 3) & ~@as(usize, 3);
    try std.testing.expectEqualStrings(",f", std.mem.sliceTo(buf[addr_padded..], 0));

    // Check float value
    const type_tag_padded = (3 + 3) & ~@as(usize, 3);
    const float_bytes = buf[addr_padded + type_tag_padded ..][0..4];
    const big_bits = std.mem.readInt(u32, float_bytes, .big);
    const decoded_f32: f32 = @bitCast(big_bits);
    try std.testing.expectApproxEqAbs(@as(f32, 0.85), decoded_f32, 0.00001);
}

test "osc bundle encoding" {
    const gpa = std.testing.allocator;
    var bundle = OscBundle.init();
    defer bundle.deinit(gpa);

    try bundle.addMessage(gpa, OscMessage.init("/avatar/parameters/v2/JawOpen", .{ .float = 0.5 }));
    try bundle.addMessage(gpa, OscMessage.init("/avatar/parameters/v2/EyeClosedLeft", .{ .float = 1.0 }));

    var buf: [512]u8 = undefined;
    const written = try bundle.encode(&buf);
    try std.testing.expect(written > 0);
    try std.testing.expectEqualStrings("#bundle", std.mem.sliceTo(buf[0..], 0));
}

test "vrcft osc encoder" {
    const gpa = std.testing.allocator;
    var data = UnifiedTrackingData.init();
    data.set(.JawOpen, 0.9);
    data.set(.EyeClosedLeft, 1.0);

    const encoder = VrcftOscEncoder{
        .config = .{
            .base_prefix = "/avatar/parameters",
            .v2_subpath = "v2",
        },
    };

    var bundle = OscBundle.init();
    defer {
        for (bundle.messages.items) |msg| {
            gpa.free(msg.address);
        }
        bundle.deinit(gpa);
    }

    try encoder.encodeTrackingDataToBundle(gpa, &data, &bundle);
    try std.testing.expect(bundle.messages.items.len == Expression.count);

    var buf: [8192]u8 = undefined;
    const len = try bundle.encode(&buf);
    try std.testing.expect(len > 0);
}
