const std = @import("std");
const vrcft_mod = struct {
    pub const expressions = @import("vrcft/expressions.zig");
    pub const osc = @import("vrcft/osc.zig");
    pub const transmitter = @import("vrcft/transmitter.zig");
};
const video_mod = struct {
    pub const frame = @import("video/frame.zig");
    pub const stream = @import("video/stream.zig");
    pub const jpeg_lite = @import("video/jpeg_lite.zig");
};
const tracking_mod = struct {
    pub const tracker = @import("tracking/tracker.zig");
    pub const filter = @import("tracking/filter.zig");
    pub const landmarks = @import("tracking/landmarks.zig");
};

pub const UnifiedTrackingData = vrcft_mod.expressions.UnifiedTrackingData;
pub const Expression = vrcft_mod.expressions.Expression;
pub const FaceTracker = tracking_mod.tracker.FaceTracker;
pub const StreamSource = video_mod.stream.StreamSource;
pub const OscTransmitter = vrcft_mod.transmitter.OscTransmitter;
pub const VrcftOscEncoder = vrcft_mod.osc.VrcftOscEncoder;
pub const VideoFrame = video_mod.frame.VideoFrame;

pub const PipelineStats = struct {
    frames_processed: u64 = 0,
    packets_transmitted: u64 = 0,
    bytes_transmitted: u64 = 0,
    last_fps: f32 = 0.0,
};

/// End-to-end streaming video to VRCFT OSC pipeline.
pub const TrackingPipeline = struct {
    allocator: std.mem.Allocator,
    source: StreamSource,
    tracker: FaceTracker,
    transmitter: ?*OscTransmitter = null,
    current_data: UnifiedTrackingData,
    stats: PipelineStats = .{},
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn init(
        allocator: std.mem.Allocator,
        source: StreamSource,
        transmitter: ?*OscTransmitter,
    ) TrackingPipeline {
        return .{
            .allocator = allocator,
            .source = source,
            .tracker = FaceTracker.init(allocator),
            .transmitter = transmitter,
            .current_data = UnifiedTrackingData.init(),
        };
    }

    pub fn deinit(self: *TrackingPipeline) void {
        self.tracker.deinit();
    }

    /// Ingests a single frame from the video stream, tracks facial expressions, and outputs VRCFT OSC.
    pub fn step(self: *TrackingPipeline) !bool {
        const maybe_frame = try self.source.nextFrame(self.allocator);
        if (maybe_frame == null) return false;

        var frame = maybe_frame.?;
        defer frame.deinit();

        try self.tracker.processFrame(&frame, &self.current_data);
        self.stats.frames_processed += 1;

        if (self.transmitter) |tx| {
            const bytes_sent = try tx.sendTrackingData(&self.current_data);
            self.stats.packets_transmitted += 1;
            self.stats.bytes_transmitted += bytes_sent;
        }

        return true;
    }

    /// Runs pipeline loop up to `max_frames` (or indefinitely if null).
    pub fn run(self: *TrackingPipeline, max_frames: ?usize) !void {
        self.running.store(true, .seq_cst);
        var count: usize = 0;

        while (self.running.load(.seq_cst)) {
            if (max_frames) |limit| {
                if (count >= limit) break;
            }

            const ok = try self.step();
            if (!ok) break;
            count += 1;
        }

        self.running.store(false, .seq_cst);
    }

    pub fn stop(self: *TrackingPipeline) void {
        self.running.store(false, .seq_cst);
    }
};

test "pipeline end-to-end processing with synthetic stream" {
    const gpa = std.testing.allocator;

    var synth = try video_mod.stream.SyntheticSource.init(gpa, 320, 240, 30);
    defer synth.deinit();

    var pipeline = TrackingPipeline.init(gpa, synth.source(), null);
    defer pipeline.deinit();

    // Process 10 frames
    try pipeline.run(10);

    try std.testing.expectEqual(@as(u64, 10), pipeline.stats.frames_processed);
    try std.testing.expect(pipeline.current_data.get(.JawOpen) >= 0.0);
}
