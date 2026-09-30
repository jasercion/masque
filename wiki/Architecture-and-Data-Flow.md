# Architecture and Data Flow

Masque is engineered as a modular, low-latency streaming pipeline that ingests raw video frames, runs computer vision facial landmark tracking, synthesizes standard Unified Expressions blendshapes, and emits Open Sound Control (OSC) datagrams over UDP.

---

## High-Level Architecture Diagram

```
+─────────────────────────────────────────────────────────────+
│                     Video Ingestion Layer                   │
│                                                             │
│  [ SyntheticSource ]              [ UdpFrameSource ]        │
│  (Procedural Engine)              (Network Socket)          │
│          │                               │                  │
│          └───────────────┬───────────────┘                  │
│                          ▼                                  │
│             [ video.VideoFrame Buffer ]                     │
│             (RGB888 / Grayscale Luminance)                  │
+──────────────────────────┬──────────────────────────────────+
                           │
                           ▼
+─────────────────────────────────────────────────────────────+
│             Feature Extraction & Signal Processing          │
│                                                             │
│                 [ FaceTracker Engine ]                      │
│                 - Ocular Gaze & Centroids                   │
│                 - Eyelid Aperture Ratios                    │
│                 - Lower Face / Mouth Bounds                 │
│                          │                                  │
│                          ▼                                  │
│                 [ Temporal Filters ]                        │
│                 - One Euro Adaptive (1€)                    │
│                 - Exponential Moving Average                │
+──────────────────────────┬──────────────────────────────────+
                           │
                           ▼
+─────────────────────────────────────────────────────────────+
│               Unified Expressions Synthesis                 │
│                                                             │
│              [ UnifiedTrackingData Table ]                  │
│         - 80+ Standard Parameters [0.0 - 1.0]               │
│         - Base Deformations & Bilateral Symmetry            │
│         - Synthesized & Blended Combinations                │
+──────────────────────────┬──────────────────────────────────+
                           │
                           ▼
+─────────────────────────────────────────────────────────────+
│             OSC Serialization & UDP Transport               │
│                                                             │
│                 [ VrcftOscEncoder ]                         │
│            - Path: /avatar/parameters/v2/...                │
│            - Float (0.0-1.0) or Binary Bits                 │
│            - 4-Byte Boundary Alignment                      │
│                          │                                  │
│                          ▼                                  │
│                 [ OscTransmitter ]                          │
│            - Chunked Bundle Batching (<1400B)               │
│            - POSIX UDP Non-blocking Socket                  │
+─────────────────────────────────────────────────────────────+
```

---

## Detailed Data Pipeline Stages

The end-to-end execution path for every video frame follows five deterministic steps:

### Stage 1: Frame Acquisition (`src/video/`)
1. `StreamSource.nextFrame(allocator)` is invoked by the coordinator.
2. In `SyntheticSource`, frame pixels are generated dynamically with moving procedural ocular discs and mouth geometry at the requested resolution (`width` x `height`) and target framerate (`fps`).
3. In `UdpFrameSource`, UDP datagrams containing raw frame payloads (or MJPEG segments scanned with `JpegScanner`) are assembled into an allocated `VideoFrame`.
4. Pixel buffers provide luminance extraction $Y = 0.299R + 0.587G + 0.114B$ via `VideoFrame.getLuminance(x, y)` without heap churn.

### Stage 2: Facial Landmark & Region-of-Interest Extraction (`src/tracking/`)
1. `FaceTracker.processFrame(frame, data)` analyzes the current frame.
2. Geometric boundaries (`FacialRegions`, `Rect`, `Point2D`) partition the frame into ocular (left/right eyes) and lower-face (mouth/jaw) regions.
3. Eye tracking locates pupil centroids relative to the eye bounding box, yielding horizontal and vertical normalized gaze offsets.
4. Eyelid tracking calculates vertical-to-horizontal aperture ratios to classify blinking, squinting, and wide-open eye states.
5. Lower face tracking extracts mouth corner displacements (smile, frown, stretch) and vertical jaw openings.

### Stage 3: Temporal Signal Filtering (`src/tracking/filter.zig`)
1. Raw computer vision detections inherently suffer from high-frequency sensor noise.
2. Signal values are passed through adaptive `OneEuroFilter` and `EmaFilter` instances:
   * **Low-velocity movement**: Cutoff frequency decreases, suppressing high-frequency jitter.
   * **High-velocity movement** (e.g. eye saccades): Cutoff frequency increases, eliminating lag.
3. Smoothed values are normalized to $[0.0, 1.0]$ ranges.

### Stage 4: Expression Normalization & Synthesis (`src/vrcft/expressions.zig`)
1. Base parameters (such as `EyeLookUpLeft`, `JawOpen`, `MouthSmileRight`) are written to `UnifiedTrackingData`.
2. Bilateral parameters and compound shape keys are computed (e.g., `BrowInnerUp` synthesized from `BrowInnerUpLeft` and `BrowInnerUpRight`, `MouthOpen` from `JawOpen`).

### Stage 5: OSC Serialization & UDP Dispatch (`src/vrcft/osc.zig`, `src/vrcft/transmitter.zig`)
1. `OscTransmitter.sendTrackingData(data)` feeds the tracking table into `VrcftOscEncoder`.
2. Parameter addresses are formatted dynamically according to `OscAddressConfig` (e.g. `/avatar/parameters/v2/JawOpen`).
3. Values are serialized into standard OSC 1.0/1.1 big-endian binary formats with 4-byte null padding.
4. If `--binary` mode is enabled, continuous floats are quantized into discrete bit parameters (`JawOpen1`, `JawOpen2`, `JawOpen4`, `JawOpen8`).
5. Messages are grouped into `#bundle` datagrams. When a bundle exceeds safe MTU boundaries (1,400 bytes), the transmitter flushes the bundle and starts a new one to prevent packet fragmentation.

---

## Memory & Resource Management Model

* **Explicit Allocator Ingestion**: Every component accepting dynamic buffers receives a `std.mem.Allocator`.
* **Zero Allocations in Hot Paths**:
  * OSC serialization uses fixed stack-allocated buffers and slice pointers.
  * `UnifiedTrackingData` stores parameter values in a compact, cache-friendly array indexed by `enum` ordinal.
  * Temporal filters maintain constant memory without dynamic arrays.
* **Deterministic Teardown**: Sockets and heap allocations are deterministically freed when structs exit scope via `deinit()`.
