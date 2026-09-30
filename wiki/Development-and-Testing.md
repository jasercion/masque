# Development and Testing

This guide details building, testing, extending, and profiling the Masque codebase.

---

## 1. Toolchain & Dependencies

* **Zig Compiler**: Standard Zig build toolchain (0.13.0+ / 0.14-dev / master).
* **Dependencies**: Zero external C/C++ third-party library dependencies; uses standard Zig library networking, POSIX socket layer, and atomic primitives.

---

## 2. Build Targets

### Build Debug Artifacts
```bash
zig build
```
Generates executable at `zig-out/bin/masque` with full debug symbols and safety assertions enabled.

### Build Optimized Release Binaries
```bash
# Maximum runtime performance (disables safety assertions)
zig build -Doptimize=ReleaseFast

# High performance with runtime safety checks preserved
zig build -Doptimize=ReleaseSafe

# Smallest binary footprint
zig build -Doptimize=ReleaseSmall
```

---

## 3. Running Unit & Integration Tests

Masque includes extensive unit tests covering the OSC serializer, Unified Expressions math, video frame buffers, computer vision filters, and the complete tracking pipeline:

```bash
zig build test --summary all
```

To run a specific test suite or test filter:

```bash
zig test src/root.zig --test-filter "osc"
zig test src/root.zig --test-filter "pipeline"
```

---

## 4. Extending Masque

### Implementing a Custom `StreamSource`

To ingest video from a novel capture device (e.g. OpenCV, V4L2, LibCamera, or WebRTC):

1. Define your backend struct with state and configuration.
2. Implement the `vtable` callbacks:

```zig
const std = @import("std");
const masque = @import("masque");
const VideoFrame = masque.video.VideoFrame;
const StreamSource = masque.video.StreamSource;

pub const CustomCameraSource = struct {
    device_index: u32,

    pub fn source(self: *CustomCameraSource) StreamSource {
        return .{
            .ptr = self,
            .vtable = &.{
                .nextFrame = nextFrameImpl,
                .deinit = deinitImpl,
            },
        };
    }

    fn nextFrameImpl(ctx: *anyopaque, allocator: std.mem.Allocator) anyerror!?VideoFrame {
        const self: *CustomCameraSource = @ptrCast(@alignCast(ctx));
        _ = self;
        // Acquire camera buffer and return VideoFrame
        var frame = try VideoFrame.init(allocator, 640, 480, .rgb888);
        return frame;
    }

    fn deinitImpl(ctx: *anyopaque) void {
        const self: *CustomCameraSource = @ptrCast(@alignCast(ctx));
        _ = self;
    }
};
```

3. Pass your `StreamSource` directly to `TrackingPipeline.init()`.

---

## 5. Memory Management & Leak Detection

* All unit tests leverage `std.testing.allocator` (which fails on any memory leak).
* Hot loops in `FaceTracker` and `VrcftOscEncoder` are zero-allocation to prevent heap fragmentation.
* When developing new features, verify that memory consumption remains flat over time:

```bash
./zig-out/bin/masque --frames 10000 --dry-run
```

---

## 6. Code Style Conventions

* Follow the standard [Zig Style Guide](https://ziglang.org/documentation/master/#Style-Guide).
* Use `camelCase` for functions and methods, `PascalCase` for structs/enums, and `snake_case` for variables and struct fields.
* Maintain explicit allocator passing: never allocate memory without taking `std.mem.Allocator` parameter.
* Format code using standard Zig formatter prior to opening PRs:

```bash
zig fmt src/ build.zig
```
