const std = @import("std");

pub const JpegDimensions = struct {
    width: u32,
    height: u32,
};

/// Lightweight JPEG stream scanner to extract JPEG images and dimensions from streaming chunks.
pub const JpegScanner = struct {
    /// Finds SOI (0xFF 0xD8) and EOI (0xFF 0xD9) in a stream buffer.
    pub fn findFrame(buffer: []const u8) ?[]const u8 {
        if (buffer.len < 4) return null;

        var start_idx: ?usize = null;
        var i: usize = 0;

        while (i < buffer.len - 1) : (i += 1) {
            if (buffer[i] == 0xFF and buffer[i + 1] == 0xD8) {
                start_idx = i;
                break;
            }
        }

        const start = start_idx orelse return null;

        var j: usize = start + 2;
        while (j < buffer.len - 1) : (j += 1) {
            if (buffer[j] == 0xFF and buffer[j + 1] == 0xD9) {
                return buffer[start .. j + 2];
            }
        }

        return null;
    }

    /// Parses image width and height from SOF0 / SOF2 marker segments in a JPEG payload.
    pub fn parseDimensions(jpeg_bytes: []const u8) ?JpegDimensions {
        if (jpeg_bytes.len < 8) return null;
        if (jpeg_bytes[0] != 0xFF or jpeg_bytes[1] != 0xD8) return null;

        var i: usize = 2;
        while (i < jpeg_bytes.len - 8) {
            if (jpeg_bytes[i] != 0xFF) {
                i += 1;
                continue;
            }

            const marker = jpeg_bytes[i + 1];
            // SOF0 (0xC0), SOF1 (0xC1), SOF2 (0xC2)
            if (marker == 0xC0 or marker == 0xC1 or marker == 0xC2) {
                const height = (@as(u32, jpeg_bytes[i + 5]) << 8) | @as(u32, jpeg_bytes[i + 6]);
                const width = (@as(u32, jpeg_bytes[i + 7]) << 8) | @as(u32, jpeg_bytes[i + 8]);
                return .{ .width = width, .height = height };
            }

            // Variable length markers have a 2-byte length
            if (marker != 0xD8 and marker != 0xD9 and marker != 0x00 and (marker < 0xD0 or marker > 0xD7)) {
                if (i + 3 >= jpeg_bytes.len) break;
                const segment_len = (@as(usize, jpeg_bytes[i + 2]) << 8) | @as(usize, jpeg_bytes[i + 3]);
                i += 2 + segment_len;
            } else {
                i += 2;
            }
        }

        return null;
    }
};

test "jpeg scanner find frame and parse dimensions" {
    // Construct a mock JPEG header containing SOI, SOF0, and EOI
    const mock_jpeg = [_]u8{
        0xAA, 0xBB, // garbage prefix
        0xFF, 0xD8, // SOI
        0xFF, 0xC0, 0x00, 0x11, 0x08, // SOF0 length 17, precision 8
        0x01, 0xE0, // height 480
        0x02, 0x80, // width 640
        0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
        0xFF, 0xD9, // EOI
        0xCC, 0xDD, // garbage suffix
    };

    const frame = JpegScanner.findFrame(&mock_jpeg);
    try std.testing.expect(frame != null);
    try std.testing.expect(frame.?.len == 23);

    const dims = JpegScanner.parseDimensions(frame.?);
    try std.testing.expect(dims != null);
    try std.testing.expectEqual(@as(u32, 640), dims.?.width);
    try std.testing.expectEqual(@as(u32, 480), dims.?.height);
}
