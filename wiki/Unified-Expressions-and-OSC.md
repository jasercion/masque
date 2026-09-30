# Unified Expressions and OSC Protocol

Masque targets the [VRCFaceTracking (VRCFT) Unified Expressions (UE)](https://docs.vrcft.io) standard, enabling avatar face tracking inside VRChat and any compatible Open Sound Control (OSC) receiver.

---

## 1. Unified Expressions Schema

The Unified Expressions specification standardizes facial blendshape names across different tracking ecosystems (Apple ARKit, HTC Vive Facial Tracker, Meta Quest Pro, OpenFace).

Masque implements the full specification categorized into the following anatomical regions:

### Ocular & Gaze (`EyeLook*`, `EyeClosed*`, `EyeDilation*`)
* **Gaze Vectors**: `EyeLookOutRight`, `EyeLookInRight`, `EyeLookUpRight`, `EyeLookDownRight`, `EyeLookOutLeft`, `EyeLookInLeft`, `EyeLookUpLeft`, `EyeLookDownLeft`
* **Eyelids**: `EyeClosedRight`, `EyeClosedLeft`, `EyeSquintRight`, `EyeSquintLeft`, `EyeWideRight`, `EyeWideLeft`
* **Pupils**: `EyeDilationRight`, `EyeDilationLeft`, `EyeConstrictRight`, `EyeConstrictLeft`

### Eyebrows (`Brow*`)
* **Base Brow Shapes**: `BrowDownRight`, `BrowDownLeft`, `BrowInnerUpRight`, `BrowInnerUpLeft`, `BrowOuterUpRight`, `BrowOuterUpLeft`, `BrowPinchRight`, `BrowPinchLeft`
* **Synthesized Blends**: `BrowInnerUp`, `BrowUpRight`, `BrowUpLeft`, `BrowUp`

### Cheeks & Nose (`Cheek*`, `Nose*`, `Nasal*`)
* **Cheeks**: `CheekPuffRight`, `CheekPuffLeft`, `CheekPuff`, `CheekSuckRight`, `CheekSuckLeft`, `CheekSuck`, `CheekSquintRight`, `CheekSquintLeft`, `CheekSquint`
* **Nose**: `NoseSneerRight`, `NoseSneerLeft`, `NoseSneer`, `NasalDilationRight`, `NasalDilationLeft`, `NasalDilation`, `NasalConstrictRight`, `NasalConstrictLeft`, `NasalConstrict`

### Jaw, Lips & Mouth (`Jaw*`, `Lip*`, `Mouth*`)
* **Jaw**: `JawOpen`, `JawRight`, `JawLeft`, `JawForward`, `JawBackward`, `JawClench`, `JawMandibleRaise`
* **Lips**: `LipSuckUpperRight/Left`, `LipSuckLowerRight/Left`, `LipFunnelUpperRight/Left`, `LipFunnelLowerRight/Left`, `LipPuckerUpperRight/Left`, `LipPuckerLowerRight/Left`
* **Mouth**: `MouthSmileRight/Left`, `MouthSmile`, `MouthFrownRight/Left`, `MouthFrown`, `MouthDimpleRight/Left`, `MouthStretchRight/Left`, `MouthPressRight/Left`, `MouthTightenerRight/Left`, `MouthOpen`

### Tongue (`Tongue*`)
* `TongueOut`, `TongueUp`, `TongueDown`, `TongueRight`, `TongueLeft`, `TongueRoll`, `TongueBendDown`, `TongueCurlUp`, `TongueSquish`, `TongueFlat`

---

## 2. Base vs. Derived Blendshapes

Avatars vary in how their animator controllers are structured. To maximize avatar compatibility:
1. Base shapes are directly estimated from geometry (e.g. `BrowInnerUpLeft` and `BrowInnerUpRight`).
2. Derived / combined blendshapes are automatically synthesized via `computeDerivedShapes()`:

$$\text{BrowInnerUp} = \frac{\text{BrowInnerUpLeft} + \text{BrowInnerUpRight}}{2}$$
$$\text{MouthSmile} = \frac{\text{MouthSmileLeft} + \text{MouthSmileRight}}{2}$$
$$\text{MouthOpen} = \text{JawOpen}$$

---

## 3. OSC Protocol Serialization

Masque implements standard OSC 1.0/1.1 message and bundle serialization with 4-byte big-endian alignment.

### Dynamic Address Generation
The OSC address is computed as:
```
/avatar/parameters/<prefix>/<ExpressionName>
```
* Default prefix: `v2` (yielding `/avatar/parameters/v2/JawOpen`).
* Configurable via `--osc-prefix <name>`.

### Float Continuous Mode
* Serializes a 32-bit IEEE 754 floating point number with type tag `,f`.
* Value range: `0.0` to `1.0`.

### Quantized Binary Mode
When avatars are constrained by VRChat's sync parameter memory budget (256 bits), binary quantization represents continuous values as individual boolean bits:

Given a normalized parameter $V \in [0.0, 1.0]$ and bit depth $N=4$:
1. Quantized integer value: $I = \text{clamp}(\lfloor V \times 15 + 0.5 \rfloor, 0, 15)$
2. Emits discrete boolean parameters:
   * `/avatar/parameters/v2/<Expression>1` $\rightarrow \text{bit}_0$
   * `/avatar/parameters/v2/<Expression>2` $\rightarrow \text{bit}_1$
   * `/avatar/parameters/v2/<Expression>4` $\rightarrow \text{bit}_2$
   * `/avatar/parameters/v2/<Expression>8` $\rightarrow \text{bit}_3$

---

## 4. OSC Bundles and UDP MTU Safety

To prevent packet fragmentation and transmission drops:
1. Messages are bundled under `#bundle` headers with 64-bit NTP timetags.
2. `OscTransmitter` tracks packet payload byte counts.
3. If adding a message causes the bundle to exceed 1,400 bytes (safely below the standard 1,500 byte Ethernet MTU), the current bundle is dispatched immediately and a new bundle is initiated.
