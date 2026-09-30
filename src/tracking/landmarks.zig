const std = @import("std");

pub const Point2D = struct {
    x: f32,
    y: f32,

    pub fn dist(self: Point2D, other: Point2D) f32 {
        const dx = self.x - other.x;
        const dy = self.y - other.y;
        return @sqrt(dx * dx + dy * dy);
    }
};

pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    pub fn contains(self: Rect, pt: Point2D) bool {
        return pt.x >= self.x and pt.x <= (self.x + self.width) and
            pt.y >= self.y and pt.y <= (self.y + self.height);
    }

    pub fn center(self: Rect) Point2D {
        return .{
            .x = self.x + self.width * 0.5,
            .y = self.y + self.height * 0.5,
        };
    }
};

/// 2D Facial Feature Region Coordinates
pub const FacialRegions = struct {
    left_eye_roi: Rect,
    right_eye_roi: Rect,
    mouth_roi: Rect,
    left_brow_roi: Rect,
    right_brow_roi: Rect,

    /// Default normalized region layout on an input face video frame.
    pub fn defaultForFrame(frame_w: u32, frame_h: u32) FacialRegions {
        const fw = @as(f32, @floatFromInt(frame_w));
        const fh = @as(f32, @floatFromInt(frame_h));

        return .{
            .left_eye_roi = .{
                .x = fw * 0.20,
                .y = fh * 0.22,
                .width = fw * 0.28,
                .height = fh * 0.22,
            },
            .right_eye_roi = .{
                .x = fw * 0.52,
                .y = fh * 0.22,
                .width = fw * 0.28,
                .height = fh * 0.22,
            },
            .left_brow_roi = .{
                .x = fw * 0.20,
                .y = fh * 0.12,
                .width = fw * 0.28,
                .height = fh * 0.12,
            },
            .right_brow_roi = .{
                .x = fw * 0.52,
                .y = fh * 0.12,
                .width = fw * 0.28,
                .height = fh * 0.12,
            },
            .mouth_roi = .{
                .x = fw * 0.30,
                .y = fh * 0.55,
                .width = fw * 0.40,
                .height = fh * 0.35,
            },
        };
    }
};

test "point and rect calculations" {
    const p1 = Point2D{ .x = 0, .y = 0 };
    const p2 = Point2D{ .x = 3, .y = 4 };
    try std.testing.expectEqual(@as(f32, 5.0), p1.dist(p2));

    const r = Rect{ .x = 10, .y = 10, .width = 20, .height = 20 };
    try std.testing.expect(r.contains(Point2D{ .x = 15, .y = 15 }));
    try std.testing.expect(!r.contains(Point2D{ .x = 5, .y = 5 }));
    try std.testing.expectEqual(Point2D{ .x = 20, .y = 20 }, r.center());
}
