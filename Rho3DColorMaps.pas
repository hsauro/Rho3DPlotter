unit Rho3DColorMaps;

{
  Colour maps and small colour helpers for TRho3DPlot.

  Each map is defined by evenly spaced anchor colours (sampled from the
  matplotlib definitions) and expanded once into a 256-entry lookup table.
  jet is included for compatibility only; prefer viridis or plasma, which are
  perceptually uniform and print well in grey.
}

interface

uses
  System.UITypes,
  System.Math;

type
  TRho3DColorMap = (cmViridis, cmPlasma, cmCoolwarm, cmGray, cmJet);

const
  ColorMapNames: array[TRho3DColorMap] of string =
    ('viridis', 'plasma', 'coolwarm', 'gray', 'jet');

/// Colour at T in 0..1 (clamped). NaN gives a fully transparent colour.
function ColorMapColor(AMap: TRho3DColorMap; const T: Double): TAlphaColor;
/// Index 0..255 into the lookup table for T (clamped).
function ColorMapIndex(const T: Double): Integer; inline;
function ColorMapLUT(AMap: TRho3DColorMap; AIndex: Integer): TAlphaColor;
function ColorMapFromName(const AName: string; ADefault: TRho3DColorMap): TRho3DColorMap;

function LerpColor(const A, B: TAlphaColor; const T: Single): TAlphaColor;
/// Multiply the RGB channels by AFactor (0..1+), keeping alpha.
function ShadeColor(const C: TAlphaColor; const AFactor: Single): TAlphaColor;
/// Multiply the alpha channel by AOpacity (0..1).
function FadeColor(const C: TAlphaColor; const AOpacity: Single): TAlphaColor;

implementation

uses
  System.SysUtils;

const
  ViridisAnchors: array[0..10] of TAlphaColor = (
    $FF440154, $FF482475, $FF414487, $FF355F8D, $FF2A788E, $FF21918C,
    $FF22A884, $FF44BF70, $FF7AD151, $FFBDDF26, $FFFDE725);
  PlasmaAnchors: array[0..10] of TAlphaColor = (
    $FF0D0887, $FF41049D, $FF6A00A8, $FF8F0DA4, $FFB12A90, $FFCC4778,
    $FFE16462, $FFF2844B, $FFFCA636, $FFFCCE25, $FFF0F921);
  CoolwarmAnchors: array[0..8] of TAlphaColor = (
    $FF3B4CC0, $FF6282EA, $FF8DB0FE, $FFB9D0F9, $FFDDDDDD, $FFF5C4AC,
    $FFF49A7B, $FFDE604D, $FFB40426);
  GrayAnchors: array[0..1] of TAlphaColor = ($FF000000, $FFFFFFFF);
  JetAnchors: array[0..8] of TAlphaColor = (
    $FF00007F, $FF0000FF, $FF007FFF, $FF00FFFF, $FF7FFF7F, $FFFFFF00,
    $FFFF7F00, $FFFF0000, $FF7F0000);

var
  LUT: array[TRho3DColorMap, 0..255] of TAlphaColor;

function LerpColor(const A, B: TAlphaColor; const T: Single): TAlphaColor;
var
  u: Single;
  ca, cb: TAlphaColorRec;
  r: TAlphaColorRec;
begin
  u := EnsureRange(T, 0, 1);
  ca := TAlphaColorRec(A);
  cb := TAlphaColorRec(B);
  r.A := Round(ca.A + (cb.A - ca.A) * u);
  r.R := Round(ca.R + (cb.R - ca.R) * u);
  r.G := Round(ca.G + (cb.G - ca.G) * u);
  r.B := Round(ca.B + (cb.B - ca.B) * u);
  Result := r.Color;
end;

function ShadeColor(const C: TAlphaColor; const AFactor: Single): TAlphaColor;
var
  r: TAlphaColorRec;
  f: Single;
begin
  f := Max(AFactor, 0);
  r := TAlphaColorRec(C);
  r.R := Min(255, Round(r.R * f));
  r.G := Min(255, Round(r.G * f));
  r.B := Min(255, Round(r.B * f));
  Result := r.Color;
end;

function FadeColor(const C: TAlphaColor; const AOpacity: Single): TAlphaColor;
var
  r: TAlphaColorRec;
begin
  r := TAlphaColorRec(C);
  r.A := Round(r.A * EnsureRange(AOpacity, 0, 1));
  Result := r.Color;
end;

procedure BuildLUT(AMap: TRho3DColorMap; const Anchors: array of TAlphaColor);
var
  i, k, n: Integer;
  t, f: Double;
begin
  n := Length(Anchors);
  for i := 0 to 255 do
  begin
    t := i / 255 * (n - 1);
    k := Min(Floor(t), n - 2);
    f := t - k;
    LUT[AMap, i] := LerpColor(Anchors[k], Anchors[k + 1], f);
  end;
end;

function ColorMapIndex(const T: Double): Integer;
begin
  if T <= 0 then
    Result := 0
  else if T >= 1 then
    Result := 255
  else
    Result := Round(T * 255);
end;

function ColorMapLUT(AMap: TRho3DColorMap; AIndex: Integer): TAlphaColor;
begin
  Result := LUT[AMap, AIndex];
end;

function ColorMapColor(AMap: TRho3DColorMap; const T: Double): TAlphaColor;
begin
  if IsNan(T) then
    Result := TAlphaColors.Null
  else
    Result := LUT[AMap, ColorMapIndex(T)];
end;

function ColorMapFromName(const AName: string; ADefault: TRho3DColorMap): TRho3DColorMap;
var
  m: TRho3DColorMap;
begin
  for m := Low(TRho3DColorMap) to High(TRho3DColorMap) do
    if SameText(ColorMapNames[m], AName) then
      Exit(m);
  Result := ADefault;
end;

initialization
  BuildLUT(cmViridis, ViridisAnchors);
  BuildLUT(cmPlasma, PlasmaAnchors);
  BuildLUT(cmCoolwarm, CoolwarmAnchors);
  BuildLUT(cmGray, GrayAnchors);
  BuildLUT(cmJet, JetAnchors);

end.
