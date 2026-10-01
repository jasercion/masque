const std = @import("std");

pub const vrcft = struct {
    pub const expressions = @import("vrcft/expressions.zig");
    pub const osc = @import("vrcft/osc.zig");
    pub const transmitter = @import("vrcft/transmitter.zig");

    pub const Expression = expressions.Expression;
    pub const UnifiedTrackingData = expressions.UnifiedTrackingData;
    pub const OscMessage = osc.OscMessage;
    pub const OscBundle = osc.OscBundle;
    pub const OscValue = osc.OscValue;
    pub const OscAddressConfig = osc.OscAddressConfig;
    pub const OutputMode = osc.OutputMode;
    pub const VrcftOscEncoder = osc.VrcftOscEncoder;
    pub const OscTransmitter = transmitter.OscTransmitter;
};

pub const video = struct {
    pub const frame = @import("video/frame.zig");
    pub const stream = @import("video/stream.zig");
    pub const jpeg_lite = @import("video/jpeg_lite.zig");
    pub const ffmpeg = @import("video/ffmpeg.zig");

    pub const VideoFrame = frame.VideoFrame;
    pub const PixelFormat = frame.PixelFormat;
    pub const StreamSource = stream.StreamSource;
    pub const SyntheticSource = stream.SyntheticSource;
    pub const UdpFrameSource = stream.UdpFrameSource;
    pub const FfmpegSource = ffmpeg.FfmpegSource;
    pub const JpegScanner = jpeg_lite.JpegScanner;
    pub const JpegDimensions = jpeg_lite.JpegDimensions;
};

pub const tracking = struct {
    pub const tracker = @import("tracking/tracker.zig");
    pub const filter = @import("tracking/filter.zig");
    pub const landmarks = @import("tracking/landmarks.zig");

    pub const FaceTracker = tracker.FaceTracker;
    pub const OneEuroFilter = filter.OneEuroFilter;
    pub const EmaFilter = filter.EmaFilter;
    pub const Point2D = landmarks.Point2D;
    pub const Rect = landmarks.Rect;
    pub const FacialRegions = landmarks.FacialRegions;
};

pub const pipeline = struct {
    pub const pipe = @import("pipeline.zig");
    pub const TrackingPipeline = pipe.TrackingPipeline;
    pub const PipelineStats = pipe.PipelineStats;
};

// Top-level aliases for common convenience
pub const UnifiedTrackingData = vrcft.UnifiedTrackingData;
pub const Expression = vrcft.Expression;
pub const VideoFrame = video.VideoFrame;
pub const FaceTracker = tracking.FaceTracker;
pub const TrackingPipeline = pipeline.TrackingPipeline;
pub const OscTransmitter = vrcft.OscTransmitter;
pub const VrcftOscEncoder = vrcft.VrcftOscEncoder;

test {
    std.testing.refAllDecls(@This());
    _ = @import("vrcft/expressions.zig");
    _ = @import("vrcft/osc.zig");
    _ = @import("vrcft/transmitter.zig");
    _ = @import("video/frame.zig");
    _ = @import("video/stream.zig");
    _ = @import("video/jpeg_lite.zig");
    _ = @import("video/ffmpeg.zig");
    _ = @import("tracking/filter.zig");
    _ = @import("tracking/landmarks.zig");
    _ = @import("tracking/tracker.zig");
    _ = @import("pipeline.zig");
}
