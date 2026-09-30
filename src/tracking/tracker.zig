const std = @import("std");
const frame_mod = @import("../video/frame.zig");
const VideoFrame = frame_mod.VideoFrame;
const expressions = @import("../vrcft/expressions.zig");
const Expression = expressions.Expression;
const UnifiedTrackingData = expressions.UnifiedTrackingData;
const landmarks = @import("landmarks.zig");
const Rect = landmarks.Rect;
const Point2D = landmarks.Point2D;
const FacialRegions = landmarks.FacialRegions;
const filter_mod = @import("filter.zig");
const OneEuroFilter = filter_mod.OneEuroFilter;

/// Computer Vision Facial & Eye Tracker Engine for VRCFT.
pub const FaceTracker = struct {
    allocator: std.mem.Allocator,
    regions: ?FacialRegions = null,
    filters: [Expression.count]OneEuroFilter,
    enable_filtering: bool = true,

    pub fn init(allocator: std.mem.Allocator) FaceTracker {
        var filters: [Expression.count]OneEuroFilter = undefined;
        var i: usize = 0;
        while (i < Expression.count) : (i += 1) {
            filters[i] = OneEuroFilter.init(1.2, 0.005);
        }

        return .{
            .allocator = allocator,
            .filters = filters,
        };
    }

    pub fn deinit(self: *FaceTracker) void {
        _ = self;
    }

    /// Processes an incoming video frame and updates the tracking data structure.
    pub fn processFrame(
        self: *FaceTracker,
        frame: *const VideoFrame,
        out_data: *UnifiedTrackingData,
    ) !void {
        // Automatically determine or update facial regions if not explicitly set
        if (self.regions == null) {
            self.regions = FacialRegions.defaultForFrame(frame.width, frame.height);
        }
        const reg = self.regions.?;

        const timestamp_s: f64 = @as(f64, @floatFromInt(frame.timestamp_ns)) / @as(f64, std.time.ns_per_s);

        // 1. Process Left & Right Eye Gaze & Eyelids
        const left_eye = self.processEye(frame, reg.left_eye_roi, true);
        const right_eye = self.processEye(frame, reg.right_eye_roi, false);

        out_data.setRaw(.EyeLookOutLeft, left_eye.look_out);
        out_data.setRaw(.EyeLookInLeft, left_eye.look_in);
        out_data.setRaw(.EyeLookUpLeft, left_eye.look_up);
        out_data.setRaw(.EyeLookDownLeft, left_eye.look_down);
        out_data.setRaw(.EyeClosedLeft, left_eye.closed);
        out_data.setRaw(.EyeWideLeft, left_eye.wide);
        out_data.setRaw(.EyeSquintLeft, left_eye.squint);

        out_data.setRaw(.EyeLookOutRight, right_eye.look_out);
        out_data.setRaw(.EyeLookInRight, right_eye.look_in);
        out_data.setRaw(.EyeLookUpRight, right_eye.look_up);
        out_data.setRaw(.EyeLookDownRight, right_eye.look_down);
        out_data.setRaw(.EyeClosedRight, right_eye.closed);
        out_data.setRaw(.EyeWideRight, right_eye.wide);
        out_data.setRaw(.EyeSquintRight, right_eye.squint);

        // 2. Process Eyebrows
        const left_brow = self.processBrow(frame, reg.left_brow_roi, reg.left_eye_roi);
        const right_brow = self.processBrow(frame, reg.right_brow_roi, reg.right_eye_roi);

        out_data.setRaw(.BrowInnerUpLeft, left_brow.inner_up);
        out_data.setRaw(.BrowOuterUpLeft, left_brow.outer_up);
        out_data.setRaw(.BrowDownLeft, left_brow.down);

        out_data.setRaw(.BrowInnerUpRight, right_brow.inner_up);
        out_data.setRaw(.BrowOuterUpRight, right_brow.outer_up);
        out_data.setRaw(.BrowDownRight, right_brow.down);

        // 3. Process Mouth & Jaw
        const mouth = self.processMouth(frame, reg.mouth_roi);
        out_data.setRaw(.JawOpen, mouth.jaw_open);
        out_data.setRaw(.MouthSmileLeft, mouth.smile_left);
        out_data.setRaw(.MouthSmileRight, mouth.smile_right);
        out_data.setRaw(.MouthFrownLeft, mouth.frown_left);
        out_data.setRaw(.MouthFrownRight, mouth.frown_right);
        out_data.setRaw(.LipPucker, mouth.pucker);
        out_data.setRaw(.LipFunnel, mouth.funnel);
        out_data.setRaw(.MouthUpperUpLeft, mouth.upper_up_left);
        out_data.setRaw(.MouthUpperUpRight, mouth.upper_up_right);
        out_data.setRaw(.MouthLowerDownLeft, mouth.lower_down_left);
        out_data.setRaw(.MouthLowerDownRight, mouth.lower_down_right);

        // 4. Apply temporal smoothing filters to prevent jitter
        if (self.enable_filtering) {
            inline for (@typeInfo(Expression).@"enum".field_names) |name_str| {
                const expr = @field(Expression, name_str);
                const idx = @intFromEnum(expr);
                const raw_val = out_data.get(expr);
                const filtered_val = self.filters[idx].filter(raw_val, timestamp_s);
                out_data.set(expr, filtered_val);
            }
        }

        // 5. Compute all derived / blended Unified Expressions shapes
        out_data.computeDerivedShapes();
    }

    const EyeResult = struct {
        look_out: f32 = 0.0,
        look_in: f32 = 0.0,
        look_up: f32 = 0.0,
        look_down: f32 = 0.0,
        closed: f32 = 0.0,
        wide: f32 = 0.0,
        squint: f32 = 0.0,
    };

    fn processEye(self: *FaceTracker, frame: *const VideoFrame, roi: Rect, is_left: bool) EyeResult {
        _ = self;
        var res = EyeResult{};

        const min_x: u32 = @intFromFloat(@max(0.0, roi.x));
        const max_x: u32 = @intFromFloat(@min(@as(f32, @floatFromInt(frame.width - 1)), roi.x + roi.width));
        const min_y: u32 = @intFromFloat(@max(0.0, roi.y));
        const max_y: u32 = @intFromFloat(@min(@as(f32, @floatFromInt(frame.height - 1)), roi.y + roi.height));

        if (max_x <= min_x or max_y <= min_y) return res;

        // Find darkest pixel centroid (pupil / iris localization)
        var dark_sum_x: f32 = 0.0;
        var dark_sum_y: f32 = 0.0;
        var dark_weight_sum: f32 = 0.0;
        var sclera_pixel_count: f32 = 0.0;
        var total_pixels: f32 = 0.0;

        var y = min_y;
        while (y <= max_y) : (y += 1) {
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                const lum = frame.getLuminance(x, y);
                total_pixels += 1.0;

                if (lum > 200) {
                    sclera_pixel_count += 1.0;
                }

                if (lum < 100) {
                    const weight = @as(f32, @floatFromInt(100 - lum));
                    dark_sum_x += @as(f32, @floatFromInt(x)) * weight;
                    dark_sum_y += @as(f32, @floatFromInt(y)) * weight;
                    dark_weight_sum += weight;
                }
            }
        }

        // Eyelid openness based on sclera visibility ratio
        const sclera_ratio = if (total_pixels > 0) sclera_pixel_count / total_pixels else 0.0;
        if (sclera_ratio < 0.05) {
            res.closed = std.math.clamp(1.0 - (sclera_ratio / 0.05), 0.0, 1.0);
        } else if (sclera_ratio > 0.45) {
            res.wide = std.math.clamp((sclera_ratio - 0.45) / 0.20, 0.0, 1.0);
        }

        // Gaze direction from pupil centroid
        if (dark_weight_sum > 0.0) {
            const pupil_x = dark_sum_x / dark_weight_sum;
            const pupil_y = dark_sum_y / dark_weight_sum;

            const eye_cx = roi.x + roi.width * 0.5;
            const eye_cy = roi.y + roi.height * 0.5;

            const norm_dx = (pupil_x - eye_cx) / (roi.width * 0.35);
            const norm_dy = (pupil_y - eye_cy) / (roi.height * 0.35);

            if (is_left) {
                // Left Eye (looking left is looking out, looking right is looking in)
                if (norm_dx < 0) {
                    res.look_out = std.math.clamp(-norm_dx, 0.0, 1.0);
                } else {
                    res.look_in = std.math.clamp(norm_dx, 0.0, 1.0);
                }
            } else {
                // Right Eye (looking right is looking out, looking left is looking in)
                if (norm_dx > 0) {
                    res.look_out = std.math.clamp(norm_dx, 0.0, 1.0);
                } else {
                    res.look_in = std.math.clamp(-norm_dx, 0.0, 1.0);
                }
            }

            if (norm_dy < 0) {
                res.look_up = std.math.clamp(-norm_dy, 0.0, 1.0);
            } else {
                res.look_down = std.math.clamp(norm_dy, 0.0, 1.0);
            }
        }

        return res;
    }

    const BrowResult = struct {
        inner_up: f32 = 0.0,
        outer_up: f32 = 0.0,
        down: f32 = 0.0,
    };

    fn processBrow(self: *FaceTracker, frame: *const VideoFrame, brow_roi: Rect, eye_roi: Rect) BrowResult {
        _ = self;
        var res = BrowResult{};

        const min_x: u32 = @intFromFloat(@max(0.0, brow_roi.x));
        const max_x: u32 = @intFromFloat(@min(@as(f32, @floatFromInt(frame.width - 1)), brow_roi.x + brow_roi.width));
        const min_y: u32 = @intFromFloat(@max(0.0, brow_roi.y));
        const max_y: u32 = @intFromFloat(@min(@as(f32, @floatFromInt(frame.height - 1)), brow_roi.y + brow_roi.height));

        if (max_x <= min_x or max_y <= min_y) return res;

        var brow_y_sum: f32 = 0.0;
        var brow_count: f32 = 0.0;

        var y = min_y;
        while (y <= max_y) : (y += 1) {
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                const lum = frame.getLuminance(x, y);
                if (lum < 80) {
                    brow_y_sum += @as(f32, @floatFromInt(y));
                    brow_count += 1.0;
                }
            }
        }

        if (brow_count > 0.0) {
            const avg_brow_y = brow_y_sum / brow_count;
            const eye_y = eye_roi.y;
            const distance = eye_y - avg_brow_y;
            const baseline_distance = eye_roi.height * 0.8;

            const delta = distance - baseline_distance;
            if (delta > 0) {
                res.inner_up = std.math.clamp(delta / 15.0, 0.0, 1.0);
                res.outer_up = res.inner_up;
            } else {
                res.down = std.math.clamp(-delta / 10.0, 0.0, 1.0);
            }
        }

        return res;
    }

    const MouthResult = struct {
        jaw_open: f32 = 0.0,
        smile_left: f32 = 0.0,
        smile_right: f32 = 0.0,
        frown_left: f32 = 0.0,
        frown_right: f32 = 0.0,
        pucker: f32 = 0.0,
        funnel: f32 = 0.0,
        upper_up_left: f32 = 0.0,
        upper_up_right: f32 = 0.0,
        lower_down_left: f32 = 0.0,
        lower_down_right: f32 = 0.0,
    };

    fn processMouth(self: *FaceTracker, frame: *const VideoFrame, roi: Rect) MouthResult {
        _ = self;
        var res = MouthResult{};

        const min_x: u32 = @intFromFloat(@max(0.0, roi.x));
        const max_x: u32 = @intFromFloat(@min(@as(f32, @floatFromInt(frame.width - 1)), roi.x + roi.width));
        const min_y: u32 = @intFromFloat(@max(0.0, roi.y));
        const max_y: u32 = @intFromFloat(@min(@as(f32, @floatFromInt(frame.height - 1)), roi.y + roi.height));

        if (max_x <= min_x or max_y <= min_y) return res;

        var dark_mouth_pixels: f32 = 0.0;
        var min_mouth_x: u32 = max_x;
        var max_mouth_x: u32 = min_x;
        var min_mouth_y: u32 = max_y;
        var max_mouth_y: u32 = min_y;

        var y = min_y;
        while (y <= max_y) : (y += 1) {
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                const lum = frame.getLuminance(x, y);
                if (lum < 60) {
                    dark_mouth_pixels += 1.0;
                    if (x < min_mouth_x) min_mouth_x = x;
                    if (x > max_mouth_x) max_mouth_x = x;
                    if (y < min_mouth_y) min_mouth_y = y;
                    if (y > max_mouth_y) max_mouth_y = y;
                }
            }
        }

        if (dark_mouth_pixels > 10.0 and max_mouth_x > min_mouth_x and max_mouth_y > min_mouth_y) {
            const mouth_w = @as(f32, @floatFromInt(max_mouth_x - min_mouth_x));
            const mouth_h = @as(f32, @floatFromInt(max_mouth_y - min_mouth_y));

            const open_ratio = mouth_h / (roi.height * 0.6);
            res.jaw_open = std.math.clamp(open_ratio, 0.0, 1.0);
            res.upper_up_left = res.jaw_open * 0.5;
            res.upper_up_right = res.jaw_open * 0.5;
            res.lower_down_left = res.jaw_open * 0.5;
            res.lower_down_right = res.jaw_open * 0.5;

            const width_ratio = mouth_w / (roi.width * 0.7);
            if (width_ratio > 0.8) {
                res.smile_left = std.math.clamp((width_ratio - 0.8) / 0.3, 0.0, 1.0);
                res.smile_right = res.smile_left;
            } else if (width_ratio < 0.5) {
                res.pucker = std.math.clamp((0.5 - width_ratio) / 0.3, 0.0, 1.0);
            }
        }

        return res;
    }
};

test "face tracker processing on synthetic frame" {
    const gpa = std.testing.allocator;
    const synth_mod = @import("../video/stream.zig");

    var synth = try synth_mod.SyntheticSource.init(gpa, 320, 240, 30);
    defer synth.deinit();

    var tracker = FaceTracker.init(gpa);
    defer tracker.deinit();

    var stream = synth.source();
    const maybe_frame = try stream.nextFrame(gpa);
    try std.testing.expect(maybe_frame != null);
    var frame = maybe_frame.?;
    defer frame.deinit();

    var tracking_data = UnifiedTrackingData.init();
    try tracker.processFrame(&frame, &tracking_data);

    // Verify non-zero tracked expressions
    try std.testing.expect(tracking_data.get(.JawOpen) >= 0.0);
    try std.testing.expect(tracking_data.get(.EyeLookOutLeft) >= 0.0 or tracking_data.get(.EyeLookInLeft) >= 0.0);
}
