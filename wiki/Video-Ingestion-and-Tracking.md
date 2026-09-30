# Video Ingestion and Tracking

The video and tracking subsystem transforms raw image streams into smooth, stable facial tracking features.

---

## 1. Video Buffer & Format Handling (`src/video/frame.zig`)

The `VideoFrame` struct represents an in-memory 2D image raster.

### Supported Pixel Formats
* `PixelFormat.rgb888`: 3 bytes per pixel $[R, G, B]$.
* `PixelFormat.grayscale`: 1 byte per pixel $[Y]$.
* `PixelFormat.bgr888`: 3 bytes per pixel $[B, G, R]$.

### Luminance Computation
For computer vision analysis, RGB pixels are converted to greyscale luminance using standard Rec. 601 ITU coefficients:

$$Y = 0.299 \cdot R + 0.587 \cdot G + 0.114 \cdot B$$

Implemented in `VideoFrame.getLuminance(x, y)` to enable fast intensity sampling.

---

## 2. Ingestion Sources (`src/video/stream.zig`)

### `SyntheticSource`
Generates deterministic, animated facial patterns for continuous integration, benchmarking, and headless testing:
* **Eye Motion**: Sinusoidal horizontal and vertical gaze oscillation ($x(t) = \sin(t), y(t) = \cos(t)$).
* **Blinking**: Periodic step function animating eyelid closure every 3–4 seconds.
* **Mouth Motion**: Sinusoidal jaw opening simulation ($A \cdot \sin^2(t)$).

### `UdpFrameSource`
Receives raw pixel or JPEG frames from external cameras and wireless VR headsets over a UDP socket. Supports non-blocking socket reads and buffer reuse to prevent memory thrashing.

### `JpegScanner` (`src/video/jpeg_lite.zig`)
A lightweight, zero-allocation JPEG stream analyzer:
* Validates Start of Image (`0xFFD8`) and End of Image (`0xFFD9`) markers.
* Parses Start of Frame (`SOF0` / `0xFFC0`) segments to extract image `width`, `height`, and precision without full decode overhead.

---

## 3. Computer Vision Feature Extraction (`src/tracking/tracker.zig`)

The `FaceTracker` partitions the incoming video frame into Region-of-Interest (ROI) bounding boxes defined in `landmarks.zig`:

### Eye & Gaze Tracking
1. Isolates the left and right eye ROIs (`Rect`).
2. Calculates minimum luminance centroid within the ROI to locate the pupil center:
   $$\bar{x} = \frac{\sum x \cdot (255 - I(x,y))}{\sum (255 - I(x,y))}, \quad \bar{y} = \frac{\sum y \cdot (255 - I(x,y))}{\sum (255 - I(x,y))}$$
3. Computes normalized gaze coordinates relative to eye center:
   * Left gaze $\rightarrow$ `EyeLookOutLeft` / `EyeLookInRight`
   * Right gaze $\rightarrow$ `EyeLookInLeft` / `EyeLookOutRight`
   * Up/Down gaze $\rightarrow$ `EyeLookUp*` / `EyeLookDown*`
4. Calculates eyelid aperture ratio $R = \frac{\text{height}}{\text{width}}$:
   * $R < R_{\text{closed}} \implies \text{EyeClosed} = 1.0$
   * $R > R_{\text{wide}} \implies \text{EyeWide} = \min(1.0, (R - R_{\text{wide}}) \times k)$

### Lower Face & Mouth Tracking
1. Extracts mouth width and height from the lower-face bounding box.
2. Vertical separation determines `JawOpen` and `MouthOpen`.
3. Horizontal extension relative to neutral state estimates `MouthSmile` and `MouthStretch`.
4. Upward/downward corner displacement maps to `MouthSmile` vs `MouthFrown`.

---

## 4. Signal Filtering and Jitter Suppression (`src/tracking/filter.zig`)

Direct optical tracking produces high-frequency noise and micro-jitter. Masque uses two filtering techniques:

### Exponential Moving Average (EMA)
Low-overhead filtering for slow-varying channels:
$$S_t = \alpha \cdot X_t + (1 - \alpha) \cdot S_{t-1}$$

### One Euro Filter (1€)
An adaptive dual-cutoff low-pass filter specifically designed for human-computer interaction:

1. **Estimate Signal Derivative (Velocity)**:
   $$\hat{\dot{X}}_t = \frac{X_t - X_{t-1}}{\Delta t}$$
   $$\dot{S}_t = \text{EMA}(\hat{\dot{X}}_t, f_{c,\text{derived}})$$

2. **Dynamically Adjust Cutoff Frequency**:
   $$f_c = f_{c,\text{min}} + \beta \cdot |\dot{S}_t|$$

3. **Filter Signal**:
   $$\alpha = \frac{1}{1 + \frac{1}{2 \pi \cdot f_c \cdot \Delta t}}$$
   $$\hat{X}_t = \alpha \cdot X_t + (1 - \alpha) \cdot \hat{X}_{t-1}$$

* When resting or moving slowly ($|\dot{S}_t| \approx 0$), $f_c \to f_{c,\text{min}}$ (heavy smoothing, zero jitter).
* When making rapid saccades or sudden expressions ($|\dot{S}_t| \gg 0$), $f_c$ increases dynamically (zero perceived latency).
