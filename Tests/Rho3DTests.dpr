program Rho3DTests;

{
  Small unit tests for the FMX-free parts of TRho3DPlot: normalisation and
  aspect (TRho3DFrame), projection (TRho3DCamera: known points map to known
  pixels), round-number ticks, colour maps and the JSON helpers.

  Build and run with Tests\run_tests.bat. Exit code 0 = all passed.
}

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Types,
  System.Math,
  System.Math.Vectors,
  System.JSON,
  System.UITypes,
  Rho3DTransform in '..\Rho3DTransform.pas',
  Rho3DColorMaps in '..\Rho3DColorMaps.pas',
  Rho3DJsonUtils in '..\Rho3DJsonUtils.pas';

var
  Passed, Failed: Integer;

procedure Check(ACond: Boolean; const AName: string);
begin
  if ACond then
    Inc(Passed)
  else
  begin
    Inc(Failed);
    Writeln('FAIL: ', AName);
  end;
end;

procedure CheckNear(const A, B: Double; const AName: string; const ATol: Double = 1E-4);
begin
  Check(Abs(A - B) <= ATol, Format('%s (got %.6g, expected %.6g)', [AName, A, B]));
end;

procedure CheckPt(const P: TPointF; const X, Y: Double; const AName: string);
begin
  CheckNear(P.X, X, AName + '.X', 1E-3);
  CheckNear(P.Y, Y, AName + '.Y', 1E-3);
end;

procedure CheckTicks(const ALo, AHi: Double; ACount: Integer;
  const AExpected: array of Double; const AStep: Double);
var
  t: TArray<Double>;
  step: Double;
  i: Integer;
  name: string;
begin
  name := Format('NiceTicks(%g, %g, %d)', [ALo, AHi, ACount]);
  t := NiceTicks(ALo, AHi, ACount, step);
  CheckNear(step, AStep, name + ' step', 1E-12);
  Check(Length(t) = Length(AExpected), Format('%s count %d, expected %d',
    [name, Length(t), Length(AExpected)]));
  if Length(t) = Length(AExpected) then
    for i := 0 to High(t) do
      CheckNear(t[i], AExpected[i], Format('%s[%d]', [name, i]), 1E-12);
end;

procedure TestFrame;
var
  f: TRho3DFrame;
  p: TPoint3D;
begin
  f.Setup(0, 10, -5, 5, 100, 200, asIndependent, 1, 1, 1);
  p := f.Normalize(0, -5, 100);
  CheckNear(p.X, -1, 'frame min x'); CheckNear(p.Y, -1, 'frame min y'); CheckNear(p.Z, -1, 'frame min z');
  p := f.Normalize(10, 5, 200);
  CheckNear(p.X, 1, 'frame max x'); CheckNear(p.Y, 1, 'frame max y'); CheckNear(p.Z, 1, 'frame max z');
  p := f.Normalize(5, 0, 150);
  CheckNear(p.X, 0, 'frame mid x'); CheckNear(p.Y, 0, 'frame mid y'); CheckNear(p.Z, 0, 'frame mid z');
  CheckNear(f.DataAxis(2, f.NormAxis(2, 175)), 175, 'frame inverse');
  Check(f.Inside(TPoint3D.Create(1, -1, 0.5)), 'inside on the box');
  Check(not f.Inside(TPoint3D.Create(1.01, 0, 0)), 'outside the box');

  // equal aspect: ranges 10, 10, 100 -> box 0.1 x 0.1 x 1
  f.Setup(0, 10, 0, 10, 0, 100, asEqual, 1, 1, 1);
  CheckNear(f.Half[0], 0.1, 'equal half x');
  CheckNear(f.Half[1], 0.1, 'equal half y');
  CheckNear(f.Half[2], 1, 'equal half z');
  p := f.Normalize(10, 0, 50);
  CheckNear(p.X, 0.1, 'equal x at max'); CheckNear(p.Y, -0.1, 'equal y at min'); CheckNear(p.Z, 0, 'equal z mid');

  // custom ratios 1 : 2 : 4
  f.Setup(0, 1, 0, 1, 0, 1, asCustom, 1, 2, 4);
  CheckNear(f.Half[0], 0.25, 'custom half x');
  CheckNear(f.Half[1], 0.5, 'custom half y');
  CheckNear(f.Half[2], 1, 'custom half z');

  // a flat axis is widened, never divided by zero
  f.Setup(3, 3, 0, 1, 0, 1, asIndependent, 1, 1, 1);
  Check(f.Hi[0] > f.Lo[0], 'degenerate axis widened');
  CheckNear(f.NormAxis(0, 3), 0, 'degenerate axis centred');
end;

procedure TestCamera;
var
  c: TRho3DCamera;
  d: TRectF;
  v: TPoint3D;
  k: Double;
begin
  d := TRectF.Create(0, 0, 200, 200);
  c.Init;
  c.Projection := ppOrthographic;
  // scale = 200 * 0.255 = 51 px per box unit; centre (100, 100)
  c.Azimuth := 0; c.Elevation := 0;
  c.Prepare(d);
  CheckNear(c.Scale, 51, 'scale');
  CheckPt(c.Project(TPoint3D.Create(0, 0, 0)), 100, 100, 'front: origin');
  CheckPt(c.Project(TPoint3D.Create(1, 0, 0)), 151, 100, 'front: +x right');
  CheckPt(c.Project(TPoint3D.Create(0, 0, 1)), 100, 49, 'front: +z up');
  CheckPt(c.Project(TPoint3D.Create(0, 1, 0)), 100, 100, 'front: +y into screen');
  CheckNear(c.ToView(TPoint3D.Create(0, 1, 0)).Z, -1, 'front: +y is far');
  CheckNear(c.ToView(TPoint3D.Create(0, -1, 0)).Z, 1, 'front: -y is near');

  c.Azimuth := 0; c.Elevation := 90;      // top
  c.Prepare(d);
  CheckPt(c.Project(TPoint3D.Create(1, 0, 0)), 151, 100, 'top: +x right');
  CheckPt(c.Project(TPoint3D.Create(0, 1, 0)), 100, 49, 'top: +y up');
  CheckNear(c.ToView(TPoint3D.Create(0, 0, 1)).Z, 1, 'top: +z toward viewer');

  c.Azimuth := 90; c.Elevation := 0;      // side
  c.Prepare(d);
  CheckPt(c.Project(TPoint3D.Create(0, 1, 0)), 151, 100, 'side: +y right');
  CheckNear(c.ToView(TPoint3D.Create(1, 0, 0)).Z, 1, 'side: +x toward viewer');

  // isometric default: origin at the centre; up stays up
  c.Init;
  c.Projection := ppOrthographic;
  c.Prepare(d);
  CheckPt(c.Project(TPoint3D.Create(0, 0, 0)), 100, 100, 'iso: origin');
  Check(c.Project(TPoint3D.Create(0, 0, 1)).Y < 100, 'iso: +z above centre');
  v := c.ToView(TPoint3D.Create(1, 1, 1));
  CheckNear(Sqr(v.X) + Sqr(v.Y) + Sqr(v.Z), 3, 'rotation keeps length');

  // zoom and pan
  c.Azimuth := 0; c.Elevation := 0; c.Zoom := 2; c.PanX := 0.1; c.PanY := -0.05;
  c.Prepare(d);
  CheckPt(c.Project(TPoint3D.Create(1, 0, 0)), 100 + 20 + 102, 100 - 10, 'zoom 2 + pan');

  // perspective: a point nearer the camera is drawn larger
  c.Init;
  c.Azimuth := 0; c.Elevation := 0;
  c.Prepare(d);
  k := 51 * 7 / (7 - 1);
  CheckPt(c.Project(TPoint3D.Create(1, -1, 0)), 100 + k, 100, 'perspective near point');
  k := 51 * 7 / (7 + 1);
  CheckPt(c.Project(TPoint3D.Create(1, 1, 0)), 100 + k, 100, 'perspective far point');
end;

procedure TestTicks;
begin
  CheckTicks(0, 1, 5, [0, 0.2, 0.4, 0.6, 0.8, 1], 0.2);
  CheckTicks(-1, 1, 5, [-1, -0.5, 0, 0.5, 1], 0.5);
  CheckTicks(-0.217, 0.99, 5, [-0.2, 0, 0.2, 0.4, 0.6, 0.8], 0.2);
  CheckTicks(0.2, 7.8, 5, [2, 4, 6], 2);
  CheckTicks(-23.5, 27.1, 5, [-20, -10, 0, 10, 20], 10);
  CheckTicks(1E6, 5E6, 4, [1E6, 2E6, 3E6, 4E6, 5E6], 1E6);
  Check(FormatTick(0.5, 0.5) = '0.5', 'format 0.5');
  Check(FormatTick(-1, 0.5) = '-1.0', 'format -1.0 (step 0.5): ' + FormatTick(-1, 0.5));
  Check(FormatTick(20, 10) = '20', 'format 20');
  Check(FormatTick(0, 0.2) = '0', 'format 0');
  Check(FormatTick(0.25, 0.05) = '0.25', 'format 0.25');
end;

procedure TestColorMaps;
begin
  Check(ColorMapColor(cmViridis, 0) = $FF440154, 'viridis 0');
  Check(ColorMapColor(cmViridis, 1) = $FFFDE725, 'viridis 1');
  Check(ColorMapColor(cmViridis, -5) = $FF440154, 'viridis clamps low');
  Check(ColorMapColor(cmPlasma, 2) = $FFF0F921, 'plasma clamps high');
  Check(ColorMapColor(cmGray, NaN) = TAlphaColors.Null, 'NaN is transparent');
  Check(Abs(Integer(TAlphaColorRec(ColorMapColor(cmGray, 0.5)).R) - 128) <= 1, 'gray mid');
  Check(ColorMapFromName('Plasma', cmViridis) = cmPlasma, 'name lookup');
  Check(ColorMapFromName('nope', cmJet) = cmJet, 'name fallback');
  Check(ShadeColor($FF808080, 0.5) = $FF404040, 'shade');
  Check(FadeColor($FF123456, 0.5) = $80123456, 'fade');
end;

procedure TestJson;
var
  o, src: TJSONObject;
  vals: TArray<Double>;
  back: TArray<Double>;
  m: TDoubleMatrix;
  i: Integer;
  ok: Boolean;
begin
  vals := [0.1 + 0.2, -1.9, 1 / 3, Pi * 1E10, 1E-300, -0.0, 42, NaN];
  src := TJSONObject.Create;
  try
    JPutVector(src, 'v', vals);
    JPutMatrix(src, 'm', [[1.5, NaN], [2.5, 3.5]]);
    JPutColor(src, 'c', $80FF0000);
    JPutFloat(src, 'nan', NaN);
    // through text and back, as a file would
    o := TJSONObject(TJSONObject.ParseJSONValue(src.ToJSON));
  finally
    src.Free;
  end;
  try
    back := JVector(o, 'v');
    ok := Length(back) = Length(vals);
    if ok then
      for i := 0 to High(vals) - 1 do
        if back[i] <> vals[i] then
        begin
          ok := False;
          Writeln('  value ', i, ' ', FloatToStr(vals[i]), ' -> ', FloatToStr(back[i]));
        end;
    Check(ok, 'doubles round-trip exactly');
    Check(IsNan(back[High(back)]), 'NaN round-trips as null');
    m := JMatrix(o, 'm');
    Check((Length(m) = 2) and (m[0][0] = 1.5) and IsNan(m[0][1]) and (m[1][1] = 3.5), 'matrix');
    Check(JColor(o, 'c', 0) = $80FF0000, 'colour #AARRGGBB');
    Check(IsNan(JFloat(o, 'nan', 1)), 'null float reads NaN');
    Check(JFloat(o, 'missing', 7) = 7, 'missing key keeps default');
    Check(JStr(nil, 'x', 'd') = 'd', 'nil object keeps default');
    Check(HexToAlphaColor('#00FF00', 0) = $FF00FF00, '6-digit colour is opaque');
  finally
    o.Free;
  end;
end;

begin
  try
    TestFrame;
    TestCamera;
    TestTicks;
    TestColorMaps;
    TestJson;
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ', E.ClassName, ': ', E.Message);
      Inc(Failed);
    end;
  end;
  Writeln(Format('%d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then
    ExitCode := 1;
end.
