const std = @import("std");
const osc = @import("osc.zig");
const expressions = @import("expressions.zig");
const UnifiedTrackingData = expressions.UnifiedTrackingData;
const VrcftOscEncoder = osc.VrcftOscEncoder;
const OscBundle = osc.OscBundle;

pub const OscTransmitter = struct {
    allocator: std.mem.Allocator,
    target_sin: std.c.sockaddr.in,
    socket_fd: std.c.fd_t,
    encoder: VrcftOscEncoder,
    buffer: []u8,
    max_bundle_bytes: usize = 4096,

    pub fn init(
        allocator: std.mem.Allocator,
        host: []const u8,
        port: u16,
        encoder: VrcftOscEncoder,
    ) !OscTransmitter {
        const ip4 = try std.Io.net.Ip4Address.parse(host, port);

        const sock_fd = std.c.socket(
            std.c.AF.INET,
            std.c.SOCK.DGRAM,
            0,
        );
        if (sock_fd < 0) return error.SocketCreationFailed;

        // Increase socket send buffer size if supported
        const sndbuf_size: c_int = 65536;
        _ = std.c.setsockopt(
            sock_fd,
            std.c.SOL.SOCKET,
            std.c.SO.SNDBUF,
            @ptrCast(&sndbuf_size),
            @sizeOf(c_int),
        );

        var sin = std.mem.zeroes(std.c.sockaddr.in);
        sin.family = std.c.AF.INET;
        sin.port = std.mem.nativeToBig(u16, port);
        sin.addr = @bitCast(ip4.bytes);

        const buf = try allocator.alloc(u8, 65536);

        return .{
            .allocator = allocator,
            .target_sin = sin,
            .socket_fd = sock_fd,
            .encoder = encoder,
            .buffer = buf,
        };
    }

    pub fn deinit(self: *OscTransmitter) void {
        _ = std.c.close(self.socket_fd);
        self.allocator.free(self.buffer);
    }

    /// Serializes and sends tracking data frames split into safe UDP datagram sizes.
    pub fn sendTrackingData(self: *OscTransmitter, data: *const UnifiedTrackingData) !usize {
        var full_bundle = OscBundle.init();
        defer {
            for (full_bundle.messages.items) |msg| {
                self.allocator.free(msg.address);
            }
            full_bundle.deinit(self.allocator);
        }

        try self.encoder.encodeTrackingDataToBundle(self.allocator, data, &full_bundle);

        var total_sent: usize = 0;
        var batch_bundle = OscBundle.init();
        defer batch_bundle.deinit(self.allocator);

        for (full_bundle.messages.items) |msg| {
            // Check if adding this message exceeds max_bundle_bytes
            const next_size = batch_bundle.encodedSize() + 4 + msg.encodedSize();
            if (next_size > self.max_bundle_bytes and batch_bundle.messages.items.len > 0) {
                const encoded_len = try batch_bundle.encode(self.buffer);
                const rc = std.c.sendto(
                    self.socket_fd,
                    self.buffer.ptr,
                    encoded_len,
                    0,
                    @ptrCast(&self.target_sin),
                    @sizeOf(std.c.sockaddr.in),
                );
                if (rc < 0) return error.SendFailed;
                total_sent += @intCast(rc);
                batch_bundle.messages.clearRetainingCapacity();
            }

            try batch_bundle.addMessage(self.allocator, msg);
        }

        if (batch_bundle.messages.items.len > 0) {
            const encoded_len = try batch_bundle.encode(self.buffer);
            const rc = std.c.sendto(
                self.socket_fd,
                self.buffer.ptr,
                encoded_len,
                0,
                @ptrCast(&self.target_sin),
                @sizeOf(std.c.sockaddr.in),
            );
            if (rc < 0) return error.SendFailed;
            total_sent += @intCast(rc);
        }

        return total_sent;
    }
};

test "transmitter creation and loopback transmission" {
    const gpa = std.testing.allocator;

    const recv_sock = std.c.socket(std.c.AF.INET, std.c.SOCK.DGRAM, 0);
    try std.testing.expect(recv_sock >= 0);
    defer _ = std.c.close(recv_sock);

    var bind_sin = std.mem.zeroes(std.c.sockaddr.in);
    bind_sin.family = std.c.AF.INET;
    bind_sin.port = 0; // OS assign port
    bind_sin.addr = @bitCast([4]u8{ 127, 0, 0, 1 });

    const bind_rc = std.c.bind(recv_sock, @ptrCast(&bind_sin), @sizeOf(std.c.sockaddr.in));
    try std.testing.expect(bind_rc == 0);

    var actual_sin = std.mem.zeroes(std.c.sockaddr.in);
    var actual_len: std.c.socklen_t = @sizeOf(std.c.sockaddr.in);
    const getname_rc = std.c.getsockname(recv_sock, @ptrCast(&actual_sin), &actual_len);
    try std.testing.expect(getname_rc == 0);

    const assigned_port = std.mem.bigToNative(u16, actual_sin.port);

    var transmitter = try OscTransmitter.init(
        gpa,
        "127.0.0.1",
        assigned_port,
        .{
            .config = .{
                .base_prefix = "/avatar/parameters",
                .v2_subpath = "v2",
            },
        },
    );
    defer transmitter.deinit();

    var data = UnifiedTrackingData.init();
    data.set(.JawOpen, 0.7);
    data.set(.EyeClosedRight, 0.4);

    const sent = try transmitter.sendTrackingData(&data);
    try std.testing.expect(sent > 0);

    var recv_buf: [65536]u8 = undefined;
    var sender_sin = std.mem.zeroes(std.c.sockaddr.in);
    var sender_len: std.c.socklen_t = @sizeOf(std.c.sockaddr.in);

    const recv_rc = std.c.recvfrom(
        recv_sock,
        &recv_buf,
        recv_buf.len,
        0,
        @ptrCast(&sender_sin),
        &sender_len,
    );
    try std.testing.expect(recv_rc > 0);
    try std.testing.expectEqualStrings("#bundle", std.mem.sliceTo(recv_buf[0..], 0));
}
