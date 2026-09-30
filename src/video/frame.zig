const std = @import("std");

pub const PixelFormat = enum {
    grayscale8,
    rgb24,
    bgr24,
    rgba32,
    bgra32,
    mjpeg,
    yuv420p,

    pub fn bytesPerPixel(self: PixelFormat) usize {
        return switch (self) {
            .grayscale8 => 1,
            .rgb24, .bgr24 => 3,
            .rgba32, .bgra32 => 4,
            .mjpeg, .yuv420p => 0, // variable / planar
        };
    }
};

/// High-performance video frame buffer representation.
pub const VideoFrame = struct {
    width: u32,
    height: u32,
    format: PixelFormat,
    stride: u32,
    timestamp_ns: u64,
    data: []u8,
    allocator: ?std.mem.Allocator = null,

    pub fn initAlloc(
        allocator: std.mem.Allocator,
        width: u32,
        height: u32,
        format: PixelFormat,
    ) !VideoFrame {
        const bpp = format.bytesPerPixel();
        const stride = width * @as(u32, @intCast(bpp));
        const total_bytes = stride * height;
        const buf = try allocator.alloc(u8, total_bytes);

        return .{
            .width = width,
            .height = height,
            .format = format,
            .stride = stride,
            .timestamp_ns = 0,
            .data = buf,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *VideoFrame) void {
        if (self.allocator) |alloc| {
            alloc.free(self.data);
            self.data = &.{};
        }
    }

    pub fn getLuminance(self: *const VideoFrame, x: u32, y: u32) u8 {
        if (x >= self.width or y >= self.height) return 0;
        const row_start = y * self.stride;

        return switch (self.format) {
            .grayscale8 => self.data[row_start + x],
            .rgb24 => {
                const idx = row_start + x * 3;
                const r: u32 = self.data[idx];
                const g: u32 = self.data[idx + 1];
                const b: u32 = self.data[idx + 2];
                return @intCast((r * 77 + g * 150 + b * 29) >> 8);
            },
            .bgr24 => {
                const idx = row_start + x * 3;
                const b: u32 = self.data[idx];
                const g: u32 = self.data[idx + 1];
                const r: u32 = self.data[idx + 2];
                return @intCast((r * 77 + g * 150 + b * 29) >> 8);
            },
            .rgba32 => {
                const idx = row_start + x * 4;
                const r: u32 = self.data[idx];
                const g: u32 = self.data[idx + 1];
                const b: u32 = self.data[idx + 2];
                return @intCast((r * 77 + g * 150 + b * 29) >> 8);
            },
            .bgra32 => {
                const idx = row_start + x * 4;
                const b: u32 = self.data[idx];
                const g: u32 = self.data[idx + 1];
                const r: u32 = self.data[idx + 2];
                return @intCast((r * 77 + g * 150 + b * 29) >> 8);
            },
            else => 0,
        };
    }

    /// Convert self into an allocated Grayscale8 frame for fast computer vision feature processing.
    pub fn toGrayscale(self: *const VideoFrame, allocator: std.mem.Allocator) !VideoFrame {
        var gray_frame = try VideoFrame.initAlloc(allocator, self.width, self.height, .grayscale8);
        gray_frame.timestamp_ns = self.timestamp_ns;

        var y: u32 = 0;
        while (y < self.height) : (y += 1) {
            var x: u32 = 0;
            while (x < self.width) : (x += 1) {
                gray_frame.data[y * gray_frame.stride + x] = self.getLuminance(x, y);
            }
        }

        return gray_frame;
    }
};

test "video frame allocation and luminance calculation" {
    const gpa = std.testing.allocator;

    var frame = try VideoFrame.initAlloc(gpa, 64, 64, .rgb24);
    defer frame.deinit();

    // Fill with red pixel at (10, 10)
    const idx = 10 * frame.stride + 10 * 3;
    frame.data[idx] = 255;
    frame.data[idx + 1] = 0;
    frame.data[idx + 2] = 0;

    const lum = frame.getLuminance(10, 10);
    try std.testing.expect(lum > 50 and lum < 90); // ~77

    var gray = try frame.toGrayscale(gpa);
    defer gray.deinit();

    try std.testing.expectEqual(lum, gray.getLuminance(10, 10));
}
