const std = @import("std");
const frame_mod = @import("frame.zig");
const VideoFrame = frame_mod.VideoFrame;
const PixelFormat = frame_mod.PixelFormat;
const JpegScanner = @import("jpeg_lite.zig").JpegScanner;

/// Generic video stream source interface.
pub const StreamSource = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        nextFrame: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) anyerror!?VideoFrame,
        deinit: *const fn (ctx: *anyopaque) void,
    };

    pub fn nextFrame(self: StreamSource, allocator: std.mem.Allocator) !?VideoFrame {
        return self.vtable.nextFrame(self.ptr, allocator);
    }

    pub fn deinit(self: StreamSource) void {
        self.vtable.deinit(self.ptr);
    }
};

/// Synthetic animated video generator for testing, calibration, and headless pipelines.
pub const SyntheticSource = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    fps: u32,
    frame_index: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, fps: u32) !SyntheticSource {
        return .{
            .allocator = allocator,
            .width = width,
            .height = height,
            .fps = fps,
        };
    }

    pub fn deinit(self: *SyntheticSource) void {
        _ = self;
    }

    pub fn source(self: *SyntheticSource) StreamSource {
        return .{
            .ptr = self,
            .vtable = &.{
                .nextFrame = nextFrameErased,
                .deinit = deinitErased,
            },
        };
    }

    fn nextFrameErased(ctx: *anyopaque, allocator: std.mem.Allocator) anyerror!?VideoFrame {
        const self: *SyntheticSource = @ptrCast(@alignCast(ctx));
        return try self.nextFrame(allocator);
    }

    fn deinitErased(ctx: *anyopaque) void {
        const self: *SyntheticSource = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    pub fn nextFrame(self: *SyntheticSource, allocator: std.mem.Allocator) !?VideoFrame {
        var frame = try VideoFrame.initAlloc(allocator, self.width, self.height, .grayscale8);
        frame.timestamp_ns = self.frame_index * (std.time.ns_per_s / self.fps);
        self.frame_index += 1;

        // Base background (light gray face skin tone ~ 180)
        @memset(frame.data, 180);

        // Animated facial simulation parameters based on time
        const t: f32 = @as(f32, @floatFromInt(self.frame_index)) / @as(f32, @floatFromInt(self.fps));
        
        // Gaze movement: horizontal sine wave, vertical cosine wave
        const gaze_x_offset: f32 = @sin(t * 2.0) * 12.0;
        const gaze_y_offset: f32 = @cos(t * 1.5) * 6.0;

        // Eye Blink: periodic closing every 3 seconds
        const blink_phase = @mod(t, 3.0);
        const is_blinking = blink_phase < 0.25;
        const eye_height: f32 = if (is_blinking) 2.0 else 14.0;

        // Draw Left Eye Region (center ~ (width * 0.35, height * 0.35))
        const left_eye_cx: f32 = @as(f32, @floatFromInt(self.width)) * 0.35;
        const left_eye_cy: f32 = @as(f32, @floatFromInt(self.height)) * 0.35;
        drawEyeRegion(&frame, left_eye_cx, left_eye_cy, 24.0, eye_height, gaze_x_offset, gaze_y_offset);

        // Draw Right Eye Region (center ~ (width * 0.65, height * 0.35))
        const right_eye_cx: f32 = @as(f32, @floatFromInt(self.width)) * 0.65;
        const right_eye_cy: f32 = @as(f32, @floatFromInt(self.height)) * 0.35;
        drawEyeRegion(&frame, right_eye_cx, right_eye_cy, 24.0, eye_height, gaze_x_offset, gaze_y_offset);

        // Draw Eyebrows
        const brow_y_offset = @sin(t * 1.0) * 4.0;
        drawEyebrow(&frame, left_eye_cx, left_eye_cy - 20.0 + brow_y_offset, 25.0);
        drawEyebrow(&frame, right_eye_cx, right_eye_cy - 20.0 + brow_y_offset, 25.0);

        // Draw Mouth Region (center ~ (width * 0.50, height * 0.70))
        const mouth_cx: f32 = @as(f32, @floatFromInt(self.width)) * 0.50;
        const mouth_cy: f32 = @as(f32, @floatFromInt(self.height)) * 0.70;
        const mouth_open: f32 = (@sin(t * 3.0) + 1.0) * 0.5 * 16.0 + 4.0; // oscillating openness
        const mouth_width: f32 = 40.0 + @cos(t * 2.0) * 8.0;
        drawMouthRegion(&frame, mouth_cx, mouth_cy, mouth_width, mouth_open);

        return frame;
    }

    fn drawEyeRegion(
        frame: *VideoFrame,
        cx: f32,
        cy: f32,
        rx: f32,
        ry: f32,
        gaze_dx: f32,
        gaze_dy: f32,
    ) void {
        const min_y: u32 = @intFromFloat(@max(0.0, cy - ry - 2.0));
        const max_y: u32 = @intFromFloat(@min(@as(f32, @floatFromInt(frame.height - 1)), cy + ry + 2.0));
        const min_x: u32 = @intFromFloat(@max(0.0, cx - rx - 2.0));
        const max_x: u32 = @intFromFloat(@min(@as(f32, @floatFromInt(frame.width - 1)), cx + rx + 2.0));

        const pupil_cx = cx + gaze_dx;
        const pupil_cy = cy + gaze_dy;
        const pupil_r: f32 = 5.0;

        var y = min_y;
        while (y <= max_y) : (y += 1) {
            const dy = @as(f32, @floatFromInt(y)) - cy;
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                const dx = @as(f32, @floatFromInt(x)) - cx;
                // Ellipse equation for eye sclera
                if ((dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) <= 1.0) {
                    // Inside eye socket -> sclera white (~240)
                    var lum: u8 = 240;

                    // Pupil / Iris circle inside eye
                    const pdx = @as(f32, @floatFromInt(x)) - pupil_cx;
                    const pdy = @as(f32, @floatFromInt(y)) - pupil_cy;
                    if (pdx * pdx + pdy * pdy <= pupil_r * pupil_r) {
                        lum = 20; // dark pupil
                    }

                    frame.data[y * frame.stride + x] = lum;
                }
            }
        }
    }

    fn drawEyebrow(frame: *VideoFrame, cx: f32, cy: f32, width: f32) void {
        const min_x: u32 = @intFromFloat(@max(0.0, cx - width * 0.5));
        const max_x: u32 = @intFromFloat(@min(@as(f32, @floatFromInt(frame.width - 1)), cx + width * 0.5));
        const y: u32 = @intFromFloat(cy);

        if (y < frame.height) {
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                frame.data[y * frame.stride + x] = 40;
                if (y + 1 < frame.height) frame.data[(y + 1) * frame.stride + x] = 40;
            }
        }
    }

    fn drawMouthRegion(frame: *VideoFrame, cx: f32, cy: f32, rx: f32, ry: f32) void {
        const min_y: u32 = @intFromFloat(@max(0.0, cy - ry));
        const max_y: u32 = @intFromFloat(@min(@as(f32, @floatFromInt(frame.height - 1)), cy + ry));
        const min_x: u32 = @intFromFloat(@max(0.0, cx - rx));
        const max_x: u32 = @intFromFloat(@min(@as(f32, @floatFromInt(frame.width - 1)), cx + rx));

        var y = min_y;
        while (y <= max_y) : (y += 1) {
            const dy = @as(f32, @floatFromInt(y)) - cy;
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                const dx = @as(f32, @floatFromInt(x)) - cx;
                if ((dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) <= 1.0) {
                    frame.data[y * frame.stride + x] = 30; // dark mouth cavity
                }
            }
        }
    }
};

/// UDP Video Stream Receiver for low-latency network streams.
pub const UdpFrameSource = struct {
    allocator: std.mem.Allocator,
    socket_fd: std.c.fd_t,
    buffer: []u8,
    width: u32,
    height: u32,

    pub fn init(allocator: std.mem.Allocator, port: u16, width: u32, height: u32) !UdpFrameSource {
        const sock_fd = std.c.socket(std.c.AF.INET, std.c.SOCK.DGRAM, 0);
        if (sock_fd < 0) return error.SocketCreationFailed;

        var sin = std.mem.zeroes(std.c.sockaddr.in);
        sin.family = std.c.AF.INET;
        sin.port = std.mem.nativeToBig(u16, port);
        sin.addr = @bitCast([4]u8{ 0, 0, 0, 0 }); // INADDR_ANY

        const bind_rc = std.c.bind(sock_fd, @ptrCast(&sin), @sizeOf(std.c.sockaddr.in));
        if (bind_rc < 0) {
            _ = std.c.close(sock_fd);
            return error.BindFailed;
        }

        const buf = try allocator.alloc(u8, 65536);

        return .{
            .allocator = allocator,
            .socket_fd = sock_fd,
            .buffer = buf,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *UdpFrameSource) void {
        _ = std.c.close(self.socket_fd);
        self.allocator.free(self.buffer);
    }

    pub fn source(self: *UdpFrameSource) StreamSource {
        return .{
            .ptr = self,
            .vtable = &.{
                .nextFrame = nextFrameErased,
                .deinit = deinitErased,
            },
        };
    }

    fn nextFrameErased(ctx: *anyopaque, allocator: std.mem.Allocator) anyerror!?VideoFrame {
        const self: *UdpFrameSource = @ptrCast(@alignCast(ctx));
        return try self.nextFrame(allocator);
    }

    fn deinitErased(ctx: *anyopaque) void {
        const self: *UdpFrameSource = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    pub fn nextFrame(self: *UdpFrameSource, allocator: std.mem.Allocator) !?VideoFrame {
        var sender_sin = std.mem.zeroes(std.c.sockaddr.in);
        var sender_len: std.c.socklen_t = @sizeOf(std.c.sockaddr.in);

        const bytes_read = std.c.recvfrom(
            self.socket_fd,
            self.buffer.ptr,
            self.buffer.len,
            0,
            @ptrCast(&sender_sin),
            &sender_len,
        );

        if (bytes_read <= 0) return null;

        const payload = self.buffer[0..@intCast(bytes_read)];

        // Check if JPEG compressed frame
        if (JpegScanner.findFrame(payload)) |jpeg_bytes| {
            var frame = try VideoFrame.initAlloc(allocator, self.width, self.height, .mjpeg);
            if (frame.data.len < jpeg_bytes.len) {
                allocator.free(frame.data);
                frame.data = try allocator.alloc(u8, jpeg_bytes.len);
            }
            @memcpy(frame.data[0..jpeg_bytes.len], jpeg_bytes);
            return frame;
        }

        // Otherwise interpret as raw luminance grayscale or uncompressed payload
        var frame = try VideoFrame.initAlloc(allocator, self.width, self.height, .grayscale8);
        const copy_len = @min(frame.data.len, payload.len);
        @memcpy(frame.data[0..copy_len], payload[0..copy_len]);
        return frame;
    }
};

test "synthetic video stream generation" {
    const gpa = std.testing.allocator;

    var synth = try SyntheticSource.init(gpa, 320, 240, 30);
    defer synth.deinit();

    var stream = synth.source();

    const maybe_frame = try stream.nextFrame(gpa);
    try std.testing.expect(maybe_frame != null);
    var frame = maybe_frame.?;
    defer frame.deinit();

    try std.testing.expectEqual(@as(u32, 320), frame.width);
    try std.testing.expectEqual(@as(u32, 240), frame.height);
    try std.testing.expectEqual(PixelFormat.grayscale8, frame.format);

    // Verify eye region has non-default luminance
    const left_eye_lum = frame.getLuminance(112, 84); // Left eye center
    try std.testing.expect(left_eye_lum != 180);
}
