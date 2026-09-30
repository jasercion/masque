const std = @import("std");

/// VRCFT Unified Expressions (UE) Standard Blendshapes and Parameters.
/// Conforms to the specification defined at https://docs.vrcft.io
pub const Expression = enum {
    // --- Eye Gaze / Tracking (Left & Right) ---
    EyeLookOutRight,
    EyeLookInRight,
    EyeLookUpRight,
    EyeLookDownRight,
    EyeLookOutLeft,
    EyeLookInLeft,
    EyeLookUpLeft,
    EyeLookDownLeft,

    // --- Eyelids ---
    EyeClosedRight,
    EyeClosedLeft,
    EyeSquintRight,
    EyeSquintLeft,
    EyeWideRight,
    EyeWideLeft,

    // --- Pupils ---
    EyeDilationRight,
    EyeDilationLeft,
    EyeConstrictRight,
    EyeConstrictLeft,

    // --- Eyebrows (Base & Blended) ---
    BrowDownRight,
    BrowDownLeft,
    BrowInnerUpRight,
    BrowInnerUpLeft,
    BrowInnerUp,
    BrowOuterUpRight,
    BrowOuterUpLeft,
    BrowUpRight,
    BrowUpLeft,
    BrowUp,
    BrowPinchRight,
    BrowPinchLeft,

    // --- Cheeks ---
    CheekPuffRight,
    CheekPuffLeft,
    CheekPuff,
    CheekSuckRight,
    CheekSuckLeft,
    CheekSuck,
    CheekSquintRight,
    CheekSquintLeft,
    CheekSquint,

    // --- Nose ---
    NoseSneerRight,
    NoseSneerLeft,
    NoseSneer,
    NasalDilationRight,
    NasalDilationLeft,
    NasalDilation,
    NasalConstrictRight,
    NasalConstrictLeft,
    NasalConstrict,

    // --- Jaw ---
    JawOpen,
    JawRight,
    JawLeft,
    JawForward,
    JawBackward,
    JawClench,
    JawMandibleRaise,

    // --- Lips (Base & Blended) ---
    LipSuckUpperRight,
    LipSuckUpperLeft,
    LipSuckUpper,
    LipSuckLowerRight,
    LipSuckLowerLeft,
    LipSuckLower,
    LipSuck,

    LipFunnelUpperRight,
    LipFunnelUpperLeft,
    LipFunnelUpper,
    LipFunnelLowerRight,
    LipFunnelLowerLeft,
    LipFunnelLower,
    LipFunnel,

    LipPuckerUpperRight,
    LipPuckerUpperLeft,
    LipPuckerUpper,
    LipPuckerLowerRight,
    LipPuckerLowerLeft,
    LipPuckerLower,
    LipPucker,

    // --- Mouth & Lip Corners ---
    MouthClosed,
    MouthUpperUpRight,
    MouthUpperUpLeft,
    MouthUpperUp,
    MouthLowerDownRight,
    MouthLowerDownLeft,
    MouthLowerDown,
    MouthOpen,
    MouthRight,
    MouthLeft,
    MouthSmileRight,
    MouthSmileLeft,
    MouthSmile,
    MouthFrownRight,
    MouthFrownLeft,
    MouthFrown,
    MouthStretchRight,
    MouthStretchLeft,
    MouthStretch,
    MouthDimpleRight,
    MouthDimpleLeft,
    MouthDimple,
    MouthPressRight,
    MouthPressLeft,
    MouthPress,
    MouthTightenerRight,
    MouthTightenerLeft,
    MouthTightener,

    // --- Tongue ---
    TongueOut,
    TongueUp,
    TongueDown,
    TongueRight,
    TongueLeft,
    TongueRoll,
    TongueBendDown,
    TongueCurlUp,
    TongueSquish,
    TongueFlat,
    TongueTwistRight,
    TongueTwistLeft,

    pub const count = @typeInfo(Expression).@"enum".field_names.len;

    pub fn name(self: Expression) []const u8 {
        return @tagName(self);
    }

    pub fn fromName(str: []const u8) ?Expression {
        inline for (@typeInfo(Expression).@"enum".field_names) |name_str| {
            if (std.mem.eql(u8, name_str, str)) {
                return @field(Expression, name_str);
            }
        }
        return null;
    }
};

/// Full representation of facial tracking state matching VRCFT Unified Expressions.
pub const UnifiedTrackingData = struct {
    values: [Expression.count]f32 = @splat(0.0),

    pub fn init() UnifiedTrackingData {
        return .{};
    }

    pub fn get(self: *const UnifiedTrackingData, expr: Expression) f32 {
        return self.values[@intFromEnum(expr)];
    }

    pub fn set(self: *UnifiedTrackingData, expr: Expression, val: f32) void {
        const clamped = std.math.clamp(val, 0.0, 1.0);
        self.values[@intFromEnum(expr)] = clamped;
    }

    pub fn setRaw(self: *UnifiedTrackingData, expr: Expression, val: f32) void {
        self.values[@intFromEnum(expr)] = val;
    }

    pub fn reset(self: *UnifiedTrackingData) void {
        @memset(&self.values, 0.0);
    }

    /// Automatically compute blended / combined shapes from base shapes according to VRCFT standards.
    pub fn computeDerivedShapes(self: *UnifiedTrackingData) void {
        // Eye Blends
        // Eyebrows
        self.set(
            .BrowInnerUp,
            (self.get(.BrowInnerUpRight) + self.get(.BrowInnerUpLeft)) * 0.5,
        );
        self.set(
            .BrowUpRight,
            (self.get(.BrowInnerUpRight) + self.get(.BrowOuterUpRight)) * 0.5,
        );
        self.set(
            .BrowUpLeft,
            (self.get(.BrowInnerUpLeft) + self.get(.BrowOuterUpLeft)) * 0.5,
        );
        self.set(
            .BrowUp,
            (self.get(.BrowUpRight) + self.get(.BrowUpLeft)) * 0.5,
        );

        // Cheeks
        self.set(.CheekPuff, (self.get(.CheekPuffRight) + self.get(.CheekPuffLeft)) * 0.5);
        self.set(.CheekSuck, (self.get(.CheekSuckRight) + self.get(.CheekSuckLeft)) * 0.5);
        self.set(.CheekSquint, (self.get(.CheekSquintRight) + self.get(.CheekSquintLeft)) * 0.5);

        // Nose
        self.set(.NoseSneer, (self.get(.NoseSneerRight) + self.get(.NoseSneerLeft)) * 0.5);
        self.set(.NasalDilation, (self.get(.NasalDilationRight) + self.get(.NasalDilationLeft)) * 0.5);
        self.set(.NasalConstrict, (self.get(.NasalConstrictRight) + self.get(.NasalConstrictLeft)) * 0.5);

        // Lips
        self.set(.LipSuckUpper, (self.get(.LipSuckUpperRight) + self.get(.LipSuckUpperLeft)) * 0.5);
        self.set(.LipSuckLower, (self.get(.LipSuckLowerRight) + self.get(.LipSuckLowerLeft)) * 0.5);
        self.set(.LipSuck, (self.get(.LipSuckUpper) + self.get(.LipSuckLower)) * 0.5);

        self.set(.LipFunnelUpper, (self.get(.LipFunnelUpperRight) + self.get(.LipFunnelUpperLeft)) * 0.5);
        self.set(.LipFunnelLower, (self.get(.LipFunnelLowerRight) + self.get(.LipFunnelLowerLeft)) * 0.5);
        self.set(.LipFunnel, (self.get(.LipFunnelUpper) + self.get(.LipFunnelLower)) * 0.5);

        self.set(.LipPuckerUpper, (self.get(.LipPuckerUpperRight) + self.get(.LipPuckerUpperLeft)) * 0.5);
        self.set(.LipPuckerLower, (self.get(.LipPuckerLowerRight) + self.get(.LipPuckerLowerLeft)) * 0.5);
        self.set(.LipPucker, (self.get(.LipPuckerUpper) + self.get(.LipPuckerLower)) * 0.5);

        // Mouth
        self.set(.MouthUpperUp, (self.get(.MouthUpperUpRight) + self.get(.MouthUpperUpLeft)) * 0.5);
        self.set(.MouthLowerDown, (self.get(.MouthLowerDownRight) + self.get(.MouthLowerDownLeft)) * 0.5);
        self.set(.MouthOpen, (self.get(.MouthUpperUp) + self.get(.MouthLowerDown)) * 0.5);

        self.set(.MouthSmile, (self.get(.MouthSmileRight) + self.get(.MouthSmileLeft)) * 0.5);
        self.set(.MouthFrown, (self.get(.MouthFrownRight) + self.get(.MouthFrownLeft)) * 0.5);
        self.set(.MouthStretch, (self.get(.MouthStretchRight) + self.get(.MouthStretchLeft)) * 0.5);
        self.set(.MouthDimple, (self.get(.MouthDimpleRight) + self.get(.MouthDimpleLeft)) * 0.5);
        self.set(.MouthPress, (self.get(.MouthPressRight) + self.get(.MouthPressLeft)) * 0.5);
        self.set(.MouthTightener, (self.get(.MouthTightenerRight) + self.get(.MouthTightenerLeft)) * 0.5);
    }
};

test "expression enum and tracking data initialization" {
    var data = UnifiedTrackingData.init();
    try std.testing.expectEqual(@as(f32, 0.0), data.get(.JawOpen));

    data.set(.JawOpen, 0.75);
    try std.testing.expectEqual(@as(f32, 0.75), data.get(.JawOpen));

    data.set(.BrowInnerUpRight, 0.8);
    data.set(.BrowInnerUpLeft, 0.4);
    data.computeDerivedShapes();
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), data.get(.BrowInnerUp), 0.0001);

    try std.testing.expectEqualStrings("JawOpen", Expression.JawOpen.name());
    try std.testing.expectEqual(Expression.JawOpen, Expression.fromName("JawOpen").?);
}
