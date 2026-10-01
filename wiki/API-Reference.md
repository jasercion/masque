# API Reference

The `masque` root module (`src/root.zig`) exposes structured namespaces for VRCFT protocol encoding, video frame ingestion, feature tracking, and pipeline execution.

```zig
const masque = @import("masque");
```

---

## 1. Module: `masque.pipeline`

Coordinates frame acquisition, computer vision processing, and OSC transmission.

### `TrackingPipeline`

```zig
pub const TrackingPipeline = struct {
    allocator: std.mem.Allocator,
    source: StreamSource,
    tracker: FaceTracker,
    transmitter: ?*OscTransmitter,
    current_data: UnifiedTrackingData,
    stats: PipelineStats,
    running: std.atomic.Value(bool),

    pub fn init(
        allocator: std.mem.Allocator,
        source: StreamSource,
        transmitter: ?*OscTransmitter,
    ) TrackingPipeline;

    pub fn deinit(self: *TrackingPipeline) void;
    pub fn step(self: *TrackingPipeline) !bool;
    pub fn run(self: *TrackingPipeline, max_frames: ?usize) !void;
    pub fn stop(self: *TrackingPipeline) void;
};
```

* `init(allocator, source, transmitter)`: Allocates and initializes tracker state and tracking data.
* `step()`: Fetches the next available frame from `source`, computes tracking metrics, updates `current_data`, and sends UDP OSC bundles via `transmitter` if attached. Returns `false` on end-of-stream.
* `run(max_frames)`: Loops calling `step()` until `max_frames` is reached, `stop()` is called, or the stream ends.
* `stop()`: Atomically signals the pipeline to stop running.

### `PipelineStats`

```zig
pub const PipelineStats = struct {
    frames_processed: u64 = 0,
    packets_transmitted: u64 = 0,
    bytes_transmitted: u64 = 0,
    last_fps: f32 = 0.0,
};
```

---

## 2. Module: `masque.vrcft`

Implements Unified Expressions data structures and OSC protocol serialisation.

### `Expression` (Enum)

Enum defining all 80+ standard Unified Expressions.

```zig
pub const Expression = enum {
    EyeLookOutRight, EyeLookInRight, EyeLookUpRight, EyeLookDownRight,
    EyeLookOutLeft, EyeLookInLeft, EyeLookUpLeft, EyeLookDownLeft,
    EyeClosedRight, EyeClosedLeft, EyeSquintRight, EyeSquintLeft,
    EyeWideRight, EyeWideLeft, EyeDilationRight, EyeDilationLeft,
    BrowDownRight, BrowDownLeft, BrowInnerUpRight, BrowInnerUpLeft, BrowInnerUp,
    BrowOuterUpRight, BrowOuterUpLeft, BrowUpRight, BrowUpLeft, BrowUp,
    CheekPuffRight, CheekPuffLeft, CheekPuff, CheekSuckRight, CheekSuckLeft,
    JawOpen, JawRight, JawLeft, JawForward, JawClench,
    MouthSmileRight, MouthSmileLeft, MouthSmile, MouthFrownRight, MouthFrownLeft,
    MouthOpen, LipPucker, LipFunnel, ...
};
```

### `UnifiedTrackingData`

Fixed-size data structure storing normalized floating point parameters $[0.0, 1.0]$.

```zig
pub const UnifiedTrackingData = struct {
    values: [COUNT]f32,

    pub fn init() UnifiedTrackingData;
    pub fn get(self: *const UnifiedTrackingData, expr: Expression) f32;
    pub fn set(self: *mut UnifiedTrackingData, expr: Expression, val: f32) void;
    pub fn reset(self: *mut UnifiedTrackingData) void;
    pub fn computeDerivedShapes(self: *mut UnifiedTrackingData) void;
};
```

### `OscTransmitter`

Manages non-blocking UDP socket transport and bundle chunking.

```zig
pub const OscTransmitter = struct {
    allocator: std.mem.Allocator,
    socket_handle: ?std.posix.socket_t,
    dest_addr: std.net.Address,
    encoder: VrcftOscEncoder,

    pub fn init(
        allocator: std.mem.Allocator,
        host: []const u8,
        port: u16,
        config: OscAddressConfig,
    ) !OscTransmitter;

    pub fn deinit(self: *OscTransmitter) void;
    pub fn sendTrackingData(self: *OscTransmitter, data: *const UnifiedTrackingData) !usize;
};
```

### `VrcftOscEncoder` & `OscAddressConfig`

Encodes tracking parameters into binary OSC 1.0/1.1 bundles.

```zig
pub const OutputMode = enum { float_continuous, binary_quantized };

pub const OscAddressConfig = struct {
    prefix: []const u8 = "v2",
    mode: OutputMode = .float_continuous,
    binary_bits: u4 = 4,
};

pub const VrcftOscEncoder = struct {
    config: OscAddressConfig,

    pub fn init(config: OscAddressConfig) VrcftOscEncoder;
    pub fn encodeExpression(
        self: *const VrcftOscEncoder,
        buffer: []u8,
        expr: Expression,
        val: f32,
    ) !usize;
};
```

---

## 3. Module: `masque.video`

Provides video buffer abstraction, stream source interfaces, and JPEG scanning.

### `VideoFrame` & `PixelFormat`

```zig
pub const PixelFormat = enum { rgb888, grayscale, bgr888 };

pub const VideoFrame = struct {
    width: u32,
    height: u32,
    format: PixelFormat,
    data: []u8,
    allocator: ?std.mem.Allocator = null,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, format: PixelFormat) !VideoFrame;
    pub fn deinit(self: *VideoFrame) void;
    pub fn getLuminance(self: *const VideoFrame, x: u32, y: u32) u8;
    pub fn getPixel(self: *const VideoFrame, x: u32, y: u32) [3]u8;
    pub fn setPixel(self: *VideoFrame, x: u32, y: u32, color: [3]u8) void;
};
```

### `StreamSource`

Polymorphic interface wrapping any frame stream provider.

```zig
pub const StreamSource = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        nextFrame: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) anyerror!?VideoFrame,
        deinit: *const fn (ctx: *anyopaque) void,
    };

    pub fn nextFrame(self: StreamSource, allocator: std.mem.Allocator) !?VideoFrame;
    pub fn deinit(self: StreamSource) void;
};
```

### `SyntheticSource`, `UdpFrameSource` & `FfmpegSource`

* `SyntheticSource`: Produces procedurally animated eye gaze, blinks, and jaw motions.
* `UdpFrameSource`: Binds to a local UDP port and reassembles incoming frame datagrams.
* `FfmpegSource`: Spawns `ffmpeg` to capture from the built-in webcam or any stream URL and reads raw grayscale frames from its stdout.

```zig
pub const FfmpegSource = struct {
    pub const Input = union(enum) {
        webcam: ?[]const u8, // device id; null = platform default
        url: []const u8,     // RTSP, HTTP MJPEG, HLS, file, ...
    };
    pub const Options = struct {
        input: Input,
        width: u32,
        height: u32,
        fps: u32,
        ffmpeg_path: []const u8 = "ffmpeg",
    };

    pub fn init(allocator: std.mem.Allocator, io: std.Io, options: Options) !FfmpegSource;
    pub fn source(self: *FfmpegSource) StreamSource;
    pub fn nextFrame(self: *FfmpegSource, allocator: std.mem.Allocator) !?VideoFrame; // null when ffmpeg exits
    pub fn deinit(self: *FfmpegSource) void; // kills the ffmpeg process
    pub fn listWebcams(io: std.Io, ffmpeg_path: []const u8) !void;
};
```

* `JpegScanner`: Scans binary streams for SOI (`0xFFD8`) and EOI (`0xFFD9`) markers and extracts dimensions from SOF0 blocks.

---

## 4. Module: `masque.tracking`

Contains facial feature extractors and signal conditioning filters.

### `FaceTracker`

```zig
pub const FaceTracker = struct {
    allocator: std.mem.Allocator,
    filter_eye_left: OneEuroFilter,
    filter_eye_right: OneEuroFilter,
    filter_jaw: OneEuroFilter,

    pub fn init(allocator: std.mem.Allocator) FaceTracker;
    pub fn deinit(self: *FaceTracker) void;
    pub fn processFrame(
        self: *FaceTracker,
        frame: *const VideoFrame,
        out_data: *UnifiedTrackingData,
    ) !void;
};
```

### `OneEuroFilter` & `EmaFilter`

```zig
pub const OneEuroFilter = struct {
    min_cutoff: f32 = 1.0,
    beta: f32 = 0.007,
    d_cutoff: f32 = 1.0,
    x_prev: ?f32 = null,
    dx_prev: f32 = 0.0,
    t_prev: ?f64 = null,

    pub fn init(min_cutoff: f32, beta: f32) OneEuroFilter;
    pub fn filter(self: *OneEuroFilter, x: f32, timestamp_sec: f64) f32;
    pub fn reset(self: *OneEuroFilter) void;
};
```
