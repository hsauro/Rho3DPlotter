unit Rho3DTransform;

{
  Pure coordinate maths for TRho3DPlot, with no FMX dependency so it can be
  unit-tested on its own (see Tests\Rho3DTests.dpr).

  Pipeline for one data point:

    data (x, y, z)  --TRho3DFrame.Normalize-->  box space
    box space       --TRho3DCamera.ToView----->  view space
    view space      --TRho3DCamera.ViewToScreen-> pixels

  Box space: the plot box is centred on the origin with half-extents
  Half[0..2] (each at most 1). With independent scaling all three are 1, so
  the data fills the cube [-1..1]^3; with equal or custom aspect the shorter
  axes are scaled down.

  View space (camera): X to the right, Y up, Z toward the viewer, so larger Z
  means nearer. Azimuth and elevation follow MATLAB's view(az, el): z is up,
  az = 0, el = 0 looks along +y (x to the right, z up); az = 90 looks along -x;
  el = 90 looks straight down z.
}

interface

uses
  System.Types,
  System.Math,
  System.Math.Vectors;

type
  TRho3DProjection = (ppPerspective, ppOrthographic);
  TRho3DAspect     = (asIndependent, asEqual, asCustom);

  /// Maps data coordinates into box space.
  TRho3DFrame = record
    Lo, Hi: array[0..2] of Double;    // data range per axis (Hi > Lo)
    Half: array[0..2] of Double;      // box half-extent per axis, max 1
    /// Set the data range and work out the box shape. A degenerate range
    /// (Hi <= Lo) is widened so normalisation never divides by zero.
    /// ARatio is only used when AAspect = asCustom.
    procedure Setup(const AXLo, AXHi, AYLo, AYHi, AZLo, AZHi: Double;
      AAspect: TRho3DAspect; const ARatioX, ARatioY, ARatioZ: Double);
    function NormAxis(AAxis: Integer; const V: Double): Double; inline;
    function Normalize(const AX, AY, AZ: Double): TPoint3D;
    /// Inverse of NormAxis (box space -> data value).
    function DataAxis(AAxis: Integer; const N: Double): Double;
    /// True when a box-space point lies inside the box (with a small tolerance).
    function Inside(const P: TPoint3D): Boolean;
  end;

  /// Orbit camera: rotation, zoom, pan and projection to a destination rect.
  TRho3DCamera = record
  private
    ca, sa, ce, se: Double;           // cos/sin of azimuth and elevation
    FCenter: TPointF;
    FScale: Double;                   // pixels per box unit (incl. zoom)
    FMinWH: Double;
  public
    Azimuth: Double;                  // degrees
    Elevation: Double;                // degrees, -90..90
    Zoom: Double;                     // 1 = default fit
    PanX, PanY: Double;               // fraction of Min(width, height)
    Projection: TRho3DProjection;
    Distance: Double;                 // camera distance in box units (perspective)
    /// Fraction of Min(width, height) covered by one box unit at Zoom = 1.
    const BaseScale = 0.255;
    procedure Init;
    /// Cache trig and scale for a destination rect. Call before projecting.
    procedure Prepare(const ADest: TRectF);
    /// Rotate a box-space point into view space.
    function ToView(const P: TPoint3D): TPoint3D; inline;
    /// Rotate a direction (no translation; same as ToView for this camera).
    function RotateVec(const V: TPoint3D): TPoint3D; inline;
    /// Perspective (or orthographic) projection of a view-space point.
    function ViewToScreen(const V: TPoint3D): TPointF; inline;
    function Project(const P: TPoint3D): TPointF;
    property Center: TPointF read FCenter;
    property Scale: Double read FScale;
    property MinWH: Double read FMinWH;
  end;

/// Round-number tick values (1, 2, 5 x 10^n) inside [ALo, AHi], about
/// ACount intervals. Also returns the step.
function NiceTicks(const ALo, AHi: Double; ACount: Integer;
  out AStep: Double): TArray<Double>;
/// Format a tick value with just enough decimals for the given step.
function FormatTick(const V, AStep: Double): string;

implementation

uses
  System.SysUtils;

{ TRho3DFrame }

procedure TRho3DFrame.Setup(const AXLo, AXHi, AYLo, AYHi, AZLo, AZHi: Double;
  AAspect: TRho3DAspect; const ARatioX, ARatioY, ARatioZ: Double);

  procedure SetAxis(A: Integer; L, H: Double);
  var
    mid, pad: Double;
  begin
    if IsNan(L) or IsNan(H) or IsInfinite(L) or IsInfinite(H) then
    begin
      L := -1; H := 1;
    end;
    if H < L then
    begin
      mid := L; L := H; H := mid;
    end;
    if (H - L) <= Max(Abs(L), Abs(H)) * 1E-12 then
    begin
      mid := (L + H) / 2;
      pad := Max(Abs(mid) * 0.1, 0.5);
      L := mid - pad;
      H := mid + pad;
    end;
    Lo[A] := L;
    Hi[A] := H;
  end;

var
  r: array[0..2] of Double;
  m: Double;
  i: Integer;
begin
  SetAxis(0, AXLo, AXHi);
  SetAxis(1, AYLo, AYHi);
  SetAxis(2, AZLo, AZHi);
  case AAspect of
    asEqual:
      for i := 0 to 2 do
        r[i] := Hi[i] - Lo[i];
    asCustom:
      begin
        r[0] := Abs(ARatioX); r[1] := Abs(ARatioY); r[2] := Abs(ARatioZ);
      end;
  else
    for i := 0 to 2 do
      r[i] := 1;
  end;
  m := Max(r[0], Max(r[1], r[2]));
  for i := 0 to 2 do
    if (m <= 0) or IsNan(r[i]) then
      Half[i] := 1
    else
      Half[i] := Max(r[i] / m, 0.02);   // keep a sliver so the box never collapses
end;

function TRho3DFrame.NormAxis(AAxis: Integer; const V: Double): Double;
begin
  Result := (2 * (V - Lo[AAxis]) / (Hi[AAxis] - Lo[AAxis]) - 1) * Half[AAxis];
end;

function TRho3DFrame.Normalize(const AX, AY, AZ: Double): TPoint3D;
begin
  Result.X := NormAxis(0, AX);
  Result.Y := NormAxis(1, AY);
  Result.Z := NormAxis(2, AZ);
end;

function TRho3DFrame.DataAxis(AAxis: Integer; const N: Double): Double;
begin
  Result := Lo[AAxis] + (N / Half[AAxis] + 1) / 2 * (Hi[AAxis] - Lo[AAxis]);
end;

function TRho3DFrame.Inside(const P: TPoint3D): Boolean;
const
  Tol = 1.0001;
begin
  Result := (Abs(P.X) <= Half[0] * Tol) and (Abs(P.Y) <= Half[1] * Tol) and
    (Abs(P.Z) <= Half[2] * Tol);
end;

{ TRho3DCamera }

procedure TRho3DCamera.Init;
begin
  Azimuth := -60;
  Elevation := 30;
  Zoom := 1;
  PanX := 0;
  PanY := 0;
  Projection := ppPerspective;
  Distance := 7;
end;

procedure TRho3DCamera.Prepare(const ADest: TRectF);
var
  az, el: Double;
begin
  az := Azimuth * Pi / 180;
  el := EnsureRange(Elevation, -90, 90) * Pi / 180;
  ca := Cos(az); sa := Sin(az);
  ce := Cos(el); se := Sin(el);
  FMinWH := Min(ADest.Width, ADest.Height);
  FScale := FMinWH * BaseScale * Zoom;
  FCenter := TPointF.Create(ADest.Left + ADest.Width / 2 + PanX * FMinWH,
    ADest.Top + ADest.Height / 2 + PanY * FMinWH);
end;

function TRho3DCamera.ToView(const P: TPoint3D): TPoint3D;
var
  xp, yp: Double;
begin
  // rotate about z by the azimuth ...
  xp := P.X * ca + P.Y * sa;
  yp := -P.X * sa + P.Y * ca;
  // ... then tilt by the elevation (right = x', up = z / y', toward = -y' / z)
  Result.X := xp;
  Result.Y := P.Z * ce + yp * se;
  Result.Z := -yp * ce + P.Z * se;
end;

function TRho3DCamera.RotateVec(const V: TPoint3D): TPoint3D;
begin
  Result := ToView(V);
end;

function TRho3DCamera.ViewToScreen(const V: TPoint3D): TPointF;
var
  k: Double;
begin
  if Projection = ppPerspective then
    k := FScale * Distance / Max(Distance - V.Z, 0.05)
  else
    k := FScale;
  Result.X := FCenter.X + V.X * k;
  Result.Y := FCenter.Y - V.Y * k;
end;

function TRho3DCamera.Project(const P: TPoint3D): TPointF;
begin
  Result := ViewToScreen(ToView(P));
end;

{ ticks }

function NiceTicks(const ALo, AHi: Double; ACount: Integer;
  out AStep: Double): TArray<Double>;
var
  range, raw, mag, f, v, first: Double;
  n, i: Integer;
begin
  Result := nil;
  AStep := 0;
  if IsNan(ALo) or IsNan(AHi) or (AHi <= ALo) then
    Exit;
  if ACount < 1 then
    ACount := 1;
  range := AHi - ALo;
  raw := range / ACount;
  // Double base: Power(10, n) would pick the Single overload and the step
  // would be off by ~1e-8, enough to drop the last tick
  mag := Power(Double(10), Floor(Log10(raw)));
  f := raw / mag;
  if f < 1.5 then f := 1
  else if f < 3 then f := 2
  else if f < 7 then f := 5
  else f := 10;
  AStep := f * mag;
  first := Ceil(ALo / AStep - 1E-6) * AStep;
  n := Floor((AHi - first) / AStep + 1E-6) + 1;
  if n < 0 then n := 0;
  if n > 200 then n := 200;
  SetLength(Result, n);
  for i := 0 to n - 1 do
  begin
    v := first + i * AStep;
    if Abs(v) < AStep * 1E-9 then
      v := 0;
    Result[i] := v;
  end;
end;

function FormatTick(const V, AStep: Double): string;
var
  decimals: Integer;
begin
  if V = 0 then
    Exit('0');
  if (Abs(V) >= 1E6) or (Abs(V) < 1E-4) then
    Exit(Format('%.3g', [V]));
  if AStep <= 0 then
    Exit(Format('%.4g', [V]));
  decimals := Max(0, -Floor(Log10(AStep) + 1E-9));
  // a step such as 2.5 x 10^n never occurs, but 0.5 needs one decimal etc.
  Result := Format('%.*f', [decimals, V]);
end;

end.
