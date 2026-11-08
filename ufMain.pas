unit ufMain;

{
  Demo for TRho3DPlot. Every feature of the component is reachable from here:
  curves (Lorenz, Rossler, Chua, streaming), scatter, surfaces, parametric
  surfaces, a surface with a curve on it, colour maps and the colour bar,
  view presets, both projections, themes, reveal animation, the property
  editor, PNG / PDF / JSON export.

  Build with /p:DCC_Define=EXPORT_SELFTEST to run the headless self-test
  (exports, JSON round trip, timing) instead; results land in
  <exe folder>\selftest_out\results.txt.
}

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  System.Math, System.Math.Vectors, System.Diagnostics,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, System.Skia,
  FMX.Skia, FMX.Layouts, FMX.Controls.Presentation, FMX.StdCtrls, FMX.ListBox,
  Rho3DPlot;

type
  // order must match cmbMode.Items in ufMain.fmx
  TDemoMode = (dmLorenz, dmRossler, dmChua, dmTraces, dmCompare, dmStream,
    dmScatter, dmSurface, dmTorus, dmCloud, dmSurfaceCurve, dmMobius,
    dmBigCurve, dmBigSurface);
  // order must match cmbSource.Items
  TStreamKind = (skLorenz, skRossler, skChua);

  TfrmMain = class(TForm)
    Layout1: TLayout;
    Layout2: TLayout;
    Layout3: TLayout;
    btnReset: TButton;
    cmbMode: TComboBox;
    chkCube: TCheckBox;
    chkAxes: TCheckBox;
    chkGrid: TCheckBox;
    chkGradient: TCheckBox;
    chkAutoRotate: TCheckBox;
    lblSpeed: TLabel;
    trkSpeed: TTrackBar;
    lblWidth: TLabel;
    trkThickness: TTrackBar;
    cmbTheme: TComboBox;
    cmbSource: TComboBox;
    chkRolling: TCheckBox;
    cmbWindow: TComboBox;
    cmbDraw: TComboBox;
    chkDepth: TCheckBox;
    chkTransparent: TCheckBox;
    btnSavePng: TButton;
    btnSavePdf: TButton;
    cmbView: TComboBox;
    chkOrtho: TCheckBox;
    cmbAspect: TComboBox;
    chkLegend: TCheckBox;
    btnReveal: TButton;
    btnProperties: TButton;
    btnSaveJson: TButton;
    btnLoadJson: TButton;
    lblInfo: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure btnResetClick(Sender: TObject);
    procedure chkCubeChange(Sender: TObject);
    procedure chkAxesChange(Sender: TObject);
    procedure chkGridChange(Sender: TObject);
    procedure chkGradientChange(Sender: TObject);
    procedure chkAutoRotateChange(Sender: TObject);
    procedure trkSpeedChange(Sender: TObject);
    procedure chkDepthChange(Sender: TObject);
    procedure cmbModeChange(Sender: TObject);
    procedure trkThicknessChange(Sender: TObject);
    procedure cmbThemeChange(Sender: TObject);
    procedure cmbSourceChange(Sender: TObject);
    procedure chkRollingChange(Sender: TObject);
    procedure cmbWindowChange(Sender: TObject);
    procedure cmbDrawChange(Sender: TObject);
    procedure btnSavePngClick(Sender: TObject);
    procedure btnSavePdfClick(Sender: TObject);
    procedure cmbViewChange(Sender: TObject);
    procedure chkOrthoChange(Sender: TObject);
    procedure cmbAspectChange(Sender: TObject);
    procedure chkLegendChange(Sender: TObject);
    procedure btnRevealClick(Sender: TObject);
    procedure btnPropertiesClick(Sender: TObject);
    procedure btnSaveJsonClick(Sender: TObject);
    procedure btnLoadJsonClick(Sender: TObject);
  private
    FPlot: TRho3DPlot;
    // cached solutions
    FT, FX, FY, FZ: TArray<Double>;          // Lorenz
    FRX, FRY, FRZ: TArray<Double>;           // Rossler
    FCX, FCY, FCZ: TArray<Double>;           // Chua
    FLMin, FLMax: TPoint3D;
    FRMin, FRMax: TPoint3D;
    FCMin, FCMax: TPoint3D;
    // live streaming state
    FTimer: TTimer;
    FStream: TRho3DSeries;
    FStreamKind: TStreamKind;
    FRolling: Boolean;
    FStreamWindow: Integer;
    FSx, FSy, FSz: Double;
    FStreamCount: Integer;
    FSyncingDraw: Boolean;
{$IFDEF EXPORT_SELFTEST}
    FSelfTestTimer: TTimer;
{$ENDIF}
    procedure ComputeLorenz;
    procedure ComputeRossler;
    procedure ComputeChua;
    procedure StopStream;
    procedure ResetScene(const ATitle: string);
    procedure ShowLorenz;
    procedure ShowRossler;
    procedure ShowChua;
    procedure ShowTraces;
    procedure ShowCompare;
    procedure ShowStream;
    procedure ShowScatter;
    procedure ShowSurface;
    procedure ShowTorus;
    procedure ShowCloud;
    procedure ShowSurfaceCurve;
    procedure ShowMobius;
    procedure ShowBigCurve;
    procedure ShowBigSurface;
    procedure SetDrawMode(AIndex: Integer);
    procedure RunCurrentMode;
    procedure OnStreamTick(Sender: TObject);
    procedure PointPicked(Sender: TObject; ASeries: TRho3DSeries;
      AIndex: Integer; const AX, AY, AZ: Double);
{$IFDEF EXPORT_SELFTEST}
    procedure RunSelfTest(Sender: TObject);
{$ENDIF}
  public
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.fmx}

uses
  System.IOUtils;

const
  // Lorenz parameters
  L_sigma = 10.0;  L_rho = 28.0;  L_beta = 8.0 / 3.0;  L_dt = 0.005;
  // Rossler parameters
  R_a = 0.2;  R_b = 0.2;  R_c = 5.7;  R_dt = 0.02;
  // Chua's circuit parameters (double-scroll)
  C_alpha = 15.6;  C_beta = 28.0;  C_m0 = -1.143;  C_m1 = -0.714;  C_dt = 0.01;
  StreamMax = 6000;   // non-rolling: stop after this many points
  // rolling-window lengths (must match cmbWindow item order)
  WinSizes: array[0..4] of Integer = (500, 1000, 1500, 2500, 4000);
  HintText = 'Drag: rotate   Right-drag: pan   Wheel: zoom   Double-click: properties   ' +
    'Keys 1-4: views   Right-click: export';

function ChuaF(const x: Double): Double;
begin
  Result := C_m1 * x + 0.5 * (C_m0 - C_m1) * (Abs(x + 1) - Abs(x - 1));
end;

function Linspace(const A, B: Double; N: Integer): TArray<Double>;
var
  i: Integer;
begin
  SetLength(Result, N);
  for i := 0 to N - 1 do
    Result[i] := A + (B - A) * i / (N - 1);
end;

function NewMatrix(ARows, ACols: Integer): TRho3DMatrix;
var
  i: Integer;
begin
  SetLength(Result, ARows);
  for i := 0 to ARows - 1 do
    SetLength(Result[i], ACols);
end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FPlot := TRho3DPlot.Create(Self);
  FPlot.Parent := Self;
  FPlot.Align := TAlignLayout.Client;
  FPlot.OnPointPicked := PointPicked;

  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 16;
  FTimer.OnTimer := OnStreamTick;

  ComputeLorenz;
  ComputeRossler;
  ComputeChua;

  cmbMode.ItemIndex := 0;
  cmbSource.ItemIndex := 0;
  cmbWindow.ItemIndex := 2;
  cmbDraw.ItemIndex := 0;
  trkSpeed.Value := 30;
  FStreamWindow := WinSizes[cmbWindow.ItemIndex];
  lblInfo.Text := HintText;
  RunCurrentMode;
end;

procedure TfrmMain.FormShow(Sender: TObject);
begin
{$IFDEF EXPORT_SELFTEST}
  // run once the form has its real size
  FSelfTestTimer := TTimer.Create(Self);
  FSelfTestTimer.Interval := 300;
  FSelfTestTimer.OnTimer := RunSelfTest;
  FSelfTestTimer.Enabled := True;
{$ENDIF}
end;

procedure TfrmMain.PointPicked(Sender: TObject; ASeries: TRho3DSeries;
  AIndex: Integer; const AX, AY, AZ: Double);
var
  t: string;
begin
  t := ASeries.Title;
  if t = '' then t := 'series';
  lblInfo.Text := Format('Picked %s #%d:  (%.5g, %.5g, %.5g)', [t, AIndex, AX, AY, AZ]);
end;

{ ---- data ---- }

procedure TfrmMain.ComputeLorenz;
const
  steps = 8000;
var
  i: Integer;
  x, y, z, dx, dy, dz: Double;
begin
  SetLength(FT, steps); SetLength(FX, steps);
  SetLength(FY, steps); SetLength(FZ, steps);
  x := 0.1; y := 0.0; z := 0.0;
  FLMin := TPoint3D.Create(x, y, z);  FLMax := FLMin;
  for i := 0 to steps - 1 do
  begin
    dx := L_sigma * (y - x);
    dy := x * (L_rho - z) - y;
    dz := x * y - L_beta * z;
    x := x + dx * L_dt; y := y + dy * L_dt; z := z + dz * L_dt;
    FT[i] := i * L_dt; FX[i] := x; FY[i] := y; FZ[i] := z;
    FLMin.X := Min(FLMin.X, x); FLMax.X := Max(FLMax.X, x);
    FLMin.Y := Min(FLMin.Y, y); FLMax.Y := Max(FLMax.Y, y);
    FLMin.Z := Min(FLMin.Z, z); FLMax.Z := Max(FLMax.Z, z);
  end;
end;

procedure TfrmMain.ComputeRossler;
const
  steps = 12000;
var
  i: Integer;
  x, y, z, dx, dy, dz: Double;
begin
  SetLength(FRX, steps); SetLength(FRY, steps); SetLength(FRZ, steps);
  x := 0.0; y := 1.0; z := 0.0;
  FRMin := TPoint3D.Create(x, y, z);  FRMax := FRMin;
  for i := 0 to steps - 1 do
  begin
    dx := -(y + z);
    dy := x + R_a * y;
    dz := R_b + z * (x - R_c);
    x := x + dx * R_dt; y := y + dy * R_dt; z := z + dz * R_dt;
    FRX[i] := x; FRY[i] := y; FRZ[i] := z;
    FRMin.X := Min(FRMin.X, x); FRMax.X := Max(FRMax.X, x);
    FRMin.Y := Min(FRMin.Y, y); FRMax.Y := Max(FRMax.Y, y);
    FRMin.Z := Min(FRMin.Z, z); FRMax.Z := Max(FRMax.Z, z);
  end;
end;

procedure TfrmMain.ComputeChua;
const
  steps = 12000;
var
  i: Integer;
  x, y, z, dx, dy, dz: Double;
begin
  SetLength(FCX, steps); SetLength(FCY, steps); SetLength(FCZ, steps);
  x := 0.7; y := 0.0; z := 0.0;
  FCMin := TPoint3D.Create(x, y, z);  FCMax := FCMin;
  for i := 0 to steps - 1 do
  begin
    dx := C_alpha * (y - x - ChuaF(x));
    dy := x - y + z;
    dz := -C_beta * y;
    x := x + dx * C_dt; y := y + dy * C_dt; z := z + dz * C_dt;
    FCX[i] := x; FCY[i] := y; FCZ[i] := z;
    FCMin.X := Min(FCMin.X, x); FCMax.X := Max(FCMax.X, x);
    FCMin.Y := Min(FCMin.Y, y); FCMax.Y := Max(FCMax.Y, y);
    FCMin.Z := Min(FCMin.Z, z); FCMax.Z := Max(FCMax.Z, z);
  end;
end;

{ ---- scenes ---- }

procedure TfrmMain.StopStream;
begin
  FTimer.Enabled := False;
  FStream := nil;
end;

// common reset for every scene
procedure TfrmMain.ResetScene(const ATitle: string);
begin
  StopStream;
  FPlot.StopReveal;
  FPlot.RevealFraction := 1;
  FPlot.ShowRevealHead := False;
  FPlot.Clear;
  FPlot.AutoScale;
  FPlot.ColorMin := NaN;
  FPlot.ColorMax := NaN;
  FPlot.ColorBarTitle := '';
  FPlot.ChartTitle := ATitle;
  FPlot.AxisTitleX := 'x';
  FPlot.AxisTitleY := 'y';
  FPlot.AxisTitleZ := 'z';
  FPlot.Aspect := TRho3DAspect(cmbAspect.ItemIndex);
end;

procedure TfrmMain.ShowLorenz;
begin
  ResetScene('Lorenz attractor');
  FPlot.SetPlotData(FX, FY, FZ);
  FPlot.Series[0].Title := 'Lorenz';
  FPlot.Series[0].UseGradient := chkGradient.IsChecked;
  FPlot.Series[0].Thickness := trkThickness.Value;
end;

procedure TfrmMain.ShowRossler;
begin
  ResetScene('Rossler attractor');
  FPlot.SetPlotData(FRX, FRY, FRZ);
  FPlot.Series[0].Title := 'Rossler';
  FPlot.Series[0].UseGradient := chkGradient.IsChecked;
  FPlot.Series[0].Thickness := trkThickness.Value;
end;

procedure TfrmMain.ShowChua;
begin
  ResetScene('Chua double scroll');
  FPlot.SetPlotData(FCX, FCY, FCZ);
  FPlot.Series[0].Title := 'Chua';
  FPlot.Series[0].UseGradient := chkGradient.IsChecked;
  FPlot.Series[0].Thickness := trkThickness.Value;
end;

// x(t), y(t), z(t) staggered along the y axis
procedure TfrmMain.ShowTraces;
var
  s: TRho3DSeries;
  i, n: Integer;
begin
  ResetScene('Lorenz components');
  FPlot.AxisTitleX := 'time';
  FPlot.AxisTitleY := 'trace';
  FPlot.AxisTitleZ := 'value';
  n := Length(FT);
  s := FPlot.AddSeries(TAlphaColors.Tomato);      s.Title := 'x(t)';
  s.Thickness := trkThickness.Value;
  for i := 0 to n - 1 do s.Points.Add(TPoint3D.Create(FT[i], 0, FX[i]));
  s := FPlot.AddSeries(TAlphaColors.Limegreen);   s.Title := 'y(t)';
  s.Thickness := trkThickness.Value;
  for i := 0 to n - 1 do s.Points.Add(TPoint3D.Create(FT[i], 1, FY[i]));
  s := FPlot.AddSeries(TAlphaColors.Deepskyblue); s.Title := 'z(t)';
  s.Thickness := trkThickness.Value;
  for i := 0 to n - 1 do s.Points.Add(TPoint3D.Create(FT[i], 2, FZ[i]));
  s.Changed;
end;

procedure TfrmMain.ShowCompare;
var
  s: TRho3DSeries;
begin
  ResetScene('Lorenz and Rossler');
  s := FPlot.AddCurve(FX, FY, FZ);   s.Title := 'Lorenz';
  s.Thickness := trkThickness.Value;
  s := FPlot.AddCurve(FRX, FRY, FRZ); s.Title := 'Rossler';
  s.Thickness := trkThickness.Value;
end;

// live streaming of the selected attractor (optionally a rolling window)
procedure TfrmMain.ShowStream;
begin
  ResetScene('Live stream');
  FStreamKind := TStreamKind(cmbSource.ItemIndex);
  FRolling := chkRolling.IsChecked;
  // freeze the frame to the attractor's full extent so it can't rescale
  case FStreamKind of
    skLorenz:
      begin
        FPlot.SetDataBounds(FLMin, FLMax);
        FSx := 0.1; FSy := 0.0; FSz := 0.0;
      end;
    skRossler:
      begin
        FPlot.SetDataBounds(FRMin, FRMax);
        FSx := 0.0; FSy := 1.0; FSz := 0.0;
      end;
    skChua:
      begin
        FPlot.SetDataBounds(FCMin, FCMax);
        FSx := 0.7; FSy := 0.0; FSz := 0.0;
      end;
  end;
  FPlot.ShowRevealHead := True;    // a dot at the newest point
  FStream := FPlot.AddSeries;
  FStream.Title := cmbSource.Items[cmbSource.ItemIndex];
  FStream.UseGradient := chkGradient.IsChecked;
  FStream.Thickness := trkThickness.Value;
  FStreamCount := 0;
  FTimer.Enabled := True;
end;

procedure TfrmMain.OnStreamTick(Sender: TObject);
const
  BatchPerTick = 15;
var
  k, excess: Integer;
  dx, dy, dz: Double;
begin
  if FStream = nil then
    Exit;
  for k := 1 to BatchPerTick do
  begin
    case FStreamKind of
      skLorenz:
        begin
          dx := L_sigma * (FSy - FSx);
          dy := FSx * (L_rho - FSz) - FSy;
          dz := FSx * FSy - L_beta * FSz;
          FSx := FSx + dx * L_dt; FSy := FSy + dy * L_dt; FSz := FSz + dz * L_dt;
        end;
      skRossler:
        begin
          dx := -(FSy + FSz);
          dy := FSx + R_a * FSy;
          dz := R_b + FSz * (FSx - R_c);
          FSx := FSx + dx * R_dt; FSy := FSy + dy * R_dt; FSz := FSz + dz * R_dt;
        end;
      skChua:
        begin
          dx := C_alpha * (FSy - FSx - ChuaF(FSx));
          dy := FSx - FSy + FSz;
          dz := -C_beta * FSy;
          FSx := FSx + dx * C_dt; FSy := FSy + dy * C_dt; FSz := FSz + dz * C_dt;
        end;
    end;
    FStream.Points.Add(TPoint3D.Create(FSx, FSy, FSz));
    Inc(FStreamCount);
  end;
  if FRolling then
  begin
    // keep only the most recent FStreamWindow points -> a moving comet tail
    excess := FStream.Count - FStreamWindow;
    if excess > 0 then
      FStream.Points.DeleteRange(0, excess);
  end
  else if FStreamCount >= StreamMax then
    FTimer.Enabled := False;
  FStream.Changed;
end;

// a small data set (3D helix) to show markers with / without lines
procedure TfrmMain.ShowScatter;
const
  N = 16;
var
  s: TRho3DSeries;
  i: Integer;
  t: Double;
begin
  ResetScene('Helix');
  s := FPlot.AddSeries(TAlphaColors.Deepskyblue);
  s.Title := 'helix';
  s.Thickness := trkThickness.Value;
  s.PointSize := 9;
  for i := 0 to N - 1 do
  begin
    t := i / (N - 1) * 4 * Pi;
    s.Points.Add(TPoint3D.Create(Cos(t), Sin(t), i));
  end;
  s.Changed;
end;

// z = sin(r) / r, coloured by height (viridis)
procedure TfrmMain.ShowSurface;
const
  N = 61;
var
  x, y: TArray<Double>;
  z: TRho3DMatrix;
  i, j: Integer;
  r: Double;
  s: TRho3DSeries;
begin
  ResetScene('z = sin(r) / r');
  x := Linspace(-10, 10, N);
  y := Linspace(-10, 10, N);
  z := NewMatrix(N, N);
  for i := 0 to N - 1 do
    for j := 0 to N - 1 do
    begin
      r := Sqrt(Sqr(x[j]) + Sqr(y[i]));
      if r < 1E-9 then z[i][j] := 1 else z[i][j] := Sin(r) / r;
    end;
  s := FPlot.AddSurface(x, y, z);
  s.Title := 'sin(r)/r';
  FPlot.ColorBarTitle := 'z';
end;

// parametric torus, one colour with Lambert shading, equal aspect
procedure TfrmMain.ShowTorus;
const
  NU = 49; NV = 25; RBig = 3; RSmall = 1;
var
  x, y, z: TRho3DMatrix;
  i, j: Integer;
  u, v: Double;
  s: TRho3DSeries;
begin
  ResetScene('Torus (shaded)');
  x := NewMatrix(NV, NU); y := NewMatrix(NV, NU); z := NewMatrix(NV, NU);
  for i := 0 to NV - 1 do
    for j := 0 to NU - 1 do
    begin
      u := 2 * Pi * j / (NU - 1);
      v := 2 * Pi * i / (NV - 1);
      x[i][j] := (RBig + RSmall * Cos(v)) * Cos(u);
      y[i][j] := (RBig + RSmall * Cos(v)) * Sin(u);
      z[i][j] := RSmall * Sin(v);
    end;
  FPlot.Aspect := asEqual;
  s := FPlot.AddParametricSurface(x, y, z);
  s.Title := 'torus';
  s.ColorByValue := False;
  s.Color := $FFE07A5F;
  s.Shaded := True;
  s.EdgeColor := $30000000;
end;

// 3000 points in three clusters, coloured by distance from the origin
procedure TfrmMain.ShowCloud;
const
  N = 3000;
var
  xs, ys, zs, vs: TArray<Double>;
  i, c: Integer;
  cx, cy, cz: Double;
  s: TRho3DSeries;
begin
  ResetScene('Point cloud coloured by radius');
  RandSeed := 42;
  SetLength(xs, N); SetLength(ys, N); SetLength(zs, N); SetLength(vs, N);
  for i := 0 to N - 1 do
  begin
    c := i mod 3;
    cx := (c - 1) * 3; cy := Sin(c * 2.1) * 2; cz := c * 1.5;
    xs[i] := cx + RandG(0, 1);
    ys[i] := cy + RandG(0, 1);
    zs[i] := cz + RandG(0, 1);
    vs[i] := Sqrt(Sqr(xs[i]) + Sqr(ys[i]) + Sqr(zs[i]));
  end;
  s := FPlot.AddScatter(xs, ys, zs);
  s.Title := 'samples';
  s.SetValues(vs);
  s.ColorMap := cmPlasma;
  s.PointSize := 5;
  FPlot.ColorBarTitle := 'radius';
end;

// translucent saddle with a trajectory running across it
procedure TfrmMain.ShowSurfaceCurve;
const
  N = 41; M = 1500;
var
  x, y, cx, cy, cz: TArray<Double>;
  z: TRho3DMatrix;
  i, j: Integer;
  t, r: Double;
  s: TRho3DSeries;
begin
  ResetScene('Path on a saddle');
  x := Linspace(-2, 2, N);
  y := Linspace(-2, 2, N);
  z := NewMatrix(N, N);
  for i := 0 to N - 1 do
    for j := 0 to N - 1 do
      z[i][j] := 0.5 * (Sqr(x[j]) - Sqr(y[i]));
  s := FPlot.AddSurface(x, y, z);
  s.Title := 'z = (x^2 - y^2)/2';
  s.ColorMap := cmCoolwarm;
  s.Opacity := 0.8;
  SetLength(cx, M); SetLength(cy, M); SetLength(cz, M);
  for i := 0 to M - 1 do
  begin
    t := i / (M - 1) * 6 * Pi;
    r := 0.3 + 1.6 * i / (M - 1);
    cx[i] := r * Cos(t);
    cy[i] := r * Sin(t);
    cz[i] := 0.5 * (Sqr(cx[i]) - Sqr(cy[i])) + 0.15;
  end;
  s := FPlot.AddCurve(cx, cy, cz);
  s.Title := 'path';
  s.Color := $FF202020;
  s.Thickness := 2.5;
  FPlot.ColorBarTitle := 'z';
end;

// Moebius strip coloured by the strip coordinate v
procedure TfrmMain.ShowMobius;
const
  NU = 81; NV = 11;
var
  x, y, z, c: TRho3DMatrix;
  i, j: Integer;
  u, v: Double;
  s: TRho3DSeries;
begin
  ResetScene('Moebius strip');
  x := NewMatrix(NV, NU); y := NewMatrix(NV, NU);
  z := NewMatrix(NV, NU); c := NewMatrix(NV, NU);
  for i := 0 to NV - 1 do
    for j := 0 to NU - 1 do
    begin
      u := 2 * Pi * j / (NU - 1);
      v := -1 + 2 * i / (NV - 1);
      x[i][j] := (1 + v / 2 * Cos(u / 2)) * Cos(u);
      y[i][j] := (1 + v / 2 * Cos(u / 2)) * Sin(u);
      z[i][j] := v / 2 * Sin(u / 2);
      c[i][j] := v;
    end;
  FPlot.Aspect := asEqual;
  s := FPlot.AddParametricSurface(x, y, z);
  s.Title := 'Moebius';
  s.SetValues(c);
  s.ColorMap := cmViridis;
  s.Shaded := True;
  FPlot.ColorBarTitle := 'v';
end;

// 100,000-point Lorenz curve (performance target: smooth rotation)
procedure TfrmMain.ShowBigCurve;
const
  steps = 100000;
var
  xs, ys, zs: TArray<Double>;
  i: Integer;
  x, y, z, dx, dy, dz: Double;
  s: TRho3DSeries;
begin
  ResetScene('100,000-point Lorenz trajectory');
  SetLength(xs, steps); SetLength(ys, steps); SetLength(zs, steps);
  x := 0.1; y := 0; z := 0;
  for i := 0 to steps - 1 do
  begin
    dx := L_sigma * (y - x);
    dy := x * (L_rho - z) - y;
    dz := x * y - L_beta * z;
    x := x + dx * 0.002; y := y + dy * 0.002; z := z + dz * 0.002;
    xs[i] := x; ys[i] := y; zs[i] := z;
  end;
  FPlot.SetPlotData(xs, ys, zs);
  s := FPlot.Series[0];
  s.Title := 'Lorenz (100k)';
  s.UseGradient := chkGradient.IsChecked;
  s.Thickness := 1;
end;

// 200 x 200 surface (performance target: >= 15 fps at full detail)
procedure TfrmMain.ShowBigSurface;
const
  N = 200;
var
  x, y: TArray<Double>;
  z: TRho3DMatrix;
  i, j: Integer;
  s: TRho3DSeries;
begin
  ResetScene('200 x 200 surface');
  x := Linspace(-3, 3, N);
  y := Linspace(-3, 3, N);
  z := NewMatrix(N, N);
  for i := 0 to N - 1 do
    for j := 0 to N - 1 do
      z[i][j] := Sin(2 * x[j]) * Cos(2 * y[i]) * Exp(-0.15 * (Sqr(x[j]) + Sqr(y[i])));
  s := FPlot.AddSurface(x, y, z);
  s.Title := 'sin(2x) cos(2y) e^(-r^2/7)';
  s.FillMode := fmFilled;     // 40,000 cells: edges would be a solid mesh
  s.Shaded := True;
  FPlot.ColorBarTitle := 'z';
end;

{ ---- mode switching ---- }

// 0 = lines, 1 = points, 2 = lines + points  (applied as master to all series)
procedure TfrmMain.SetDrawMode(AIndex: Integer);
begin
  FSyncingDraw := True;
  cmbDraw.ItemIndex := AIndex;
  FSyncingDraw := False;
  case AIndex of
    0: begin FPlot.ShowLines := True;  FPlot.ShowPoints := False; end;
    1: begin FPlot.ShowLines := False; FPlot.ShowPoints := True;  end;
    2: begin FPlot.ShowLines := True;  FPlot.ShowPoints := True;  end;
  end;
end;

procedure TfrmMain.RunCurrentMode;
var
  mode: TDemoMode;
begin
  mode := TDemoMode(cmbMode.ItemIndex);
  case mode of
    dmLorenz:       ShowLorenz;
    dmRossler:      ShowRossler;
    dmChua:         ShowChua;
    dmTraces:       ShowTraces;
    dmCompare:      ShowCompare;
    dmStream:       ShowStream;
    dmScatter:      ShowScatter;
    dmSurface:      ShowSurface;
    dmTorus:        ShowTorus;
    dmCloud:        ShowCloud;
    dmSurfaceCurve: ShowSurfaceCurve;
    dmMobius:       ShowMobius;
    dmBigCurve:     ShowBigCurve;
    dmBigSurface:   ShowBigSurface;
  end;
  if mode = dmScatter then
    SetDrawMode(2)
  else
    SetDrawMode(0);
  lblInfo.Text := HintText;
end;

procedure TfrmMain.cmbModeChange(Sender: TObject);
begin
  RunCurrentMode;
end;

procedure TfrmMain.cmbSourceChange(Sender: TObject);
begin
  if TDemoMode(cmbMode.ItemIndex) = dmStream then
    ShowStream;
end;

procedure TfrmMain.chkRollingChange(Sender: TObject);
begin
  if TDemoMode(cmbMode.ItemIndex) = dmStream then
    ShowStream;
end;

procedure TfrmMain.cmbWindowChange(Sender: TObject);
begin
  FStreamWindow := WinSizes[cmbWindow.ItemIndex];
end;

{ ---- view and style controls ---- }

procedure TfrmMain.btnResetClick(Sender: TObject);
begin
  FPlot.ResetView;
end;

procedure TfrmMain.cmbViewChange(Sender: TObject);
begin
  if cmbView.ItemIndex >= 0 then
    FPlot.ViewPreset(TRho3DViewPreset(cmbView.ItemIndex));
end;

procedure TfrmMain.chkOrthoChange(Sender: TObject);
begin
  if chkOrtho.IsChecked then
    FPlot.Projection := ppOrthographic
  else
    FPlot.Projection := ppPerspective;
end;

procedure TfrmMain.cmbAspectChange(Sender: TObject);
begin
  FPlot.Aspect := TRho3DAspect(cmbAspect.ItemIndex);
end;

procedure TfrmMain.chkLegendChange(Sender: TObject);
begin
  FPlot.LegendVisible := chkLegend.IsChecked;
end;

procedure TfrmMain.chkCubeChange(Sender: TObject);
begin
  FPlot.ShowCube := chkCube.IsChecked;
end;

procedure TfrmMain.chkAxesChange(Sender: TObject);
begin
  FPlot.ShowAxes := chkAxes.IsChecked;
end;

procedure TfrmMain.chkGridChange(Sender: TObject);
begin
  FPlot.ShowGrid := chkGrid.IsChecked;
end;

procedure TfrmMain.chkGradientChange(Sender: TObject);
begin
  FPlot.UseGradient := chkGradient.IsChecked;
end;

procedure TfrmMain.chkAutoRotateChange(Sender: TObject);
begin
  FPlot.AutoRotate := chkAutoRotate.IsChecked;
end;

procedure TfrmMain.trkSpeedChange(Sender: TObject);
begin
  FPlot.AutoRotateSpeed := trkSpeed.Value;
end;

procedure TfrmMain.chkDepthChange(Sender: TObject);
begin
  FPlot.DepthCue := chkDepth.IsChecked;
end;

procedure TfrmMain.cmbDrawChange(Sender: TObject);
begin
  if FSyncingDraw then
    Exit;
  SetDrawMode(cmbDraw.ItemIndex);
end;

procedure TfrmMain.trkThicknessChange(Sender: TObject);
begin
  FPlot.LineThickness := trkThickness.Value;
end;

procedure TfrmMain.cmbThemeChange(Sender: TObject);
begin
  case cmbTheme.ItemIndex of
    0: FPlot.Theme := thLight;
    1: FPlot.Theme := thDark;
    2: begin
         FPlot.Theme := thDark;
         FPlot.BackgroundColor := $FF0B1E3A;
         FPlot.AxisColor := TAlphaColors.Lightsteelblue;
         FPlot.TextColor := TAlphaColors.White;
       end;
  end;
end;

procedure TfrmMain.btnRevealClick(Sender: TObject);
begin
  FPlot.ShowRevealHead := True;
  FPlot.AnimateReveal(6);
end;

procedure TfrmMain.btnPropertiesClick(Sender: TObject);
begin
  FPlot.ShowEditor;
end;

procedure TfrmMain.btnSavePngClick(Sender: TObject);
var
  dlg: TSaveDialog;
begin
  dlg := TSaveDialog.Create(nil);
  try
    dlg.Filter := 'PNG image (*.png)|*.png';
    dlg.DefaultExt := 'png';
    dlg.FileName := 'plot.png';
    if dlg.Execute then
      // 2x the on-screen size, laid out like the screen
      FPlot.SaveToPNG(dlg.FileName, Round(FPlot.Width * 2), Round(FPlot.Height * 2),
        chkTransparent.IsChecked);
  finally
    dlg.Free;
  end;
end;

procedure TfrmMain.btnSavePdfClick(Sender: TObject);
var
  dlg: TSaveDialog;
begin
  dlg := TSaveDialog.Create(nil);
  try
    dlg.Filter := 'PDF document (*.pdf)|*.pdf';
    dlg.DefaultExt := 'pdf';
    dlg.FileName := 'plot.pdf';
    if dlg.Execute then
      FPlot.SaveToPDF(dlg.FileName);
  finally
    dlg.Free;
  end;
end;

procedure TfrmMain.btnSaveJsonClick(Sender: TObject);
var
  dlg: TSaveDialog;
begin
  dlg := TSaveDialog.Create(nil);
  try
    dlg.Filter := 'Plot JSON (*.json)|*.json';
    dlg.DefaultExt := 'json';
    dlg.FileName := 'plot3d.json';
    if dlg.Execute then
      FPlot.SavePlotToFile(dlg.FileName);
  finally
    dlg.Free;
  end;
end;

procedure TfrmMain.btnLoadJsonClick(Sender: TObject);
var
  dlg: TOpenDialog;
begin
  dlg := TOpenDialog.Create(nil);
  try
    dlg.Filter := 'Plot JSON (*.json)|*.json';
    if dlg.Execute then
    begin
      StopStream;
      FPlot.LoadPlotFromFile(dlg.FileName);
    end;
  finally
    dlg.Free;
  end;
end;

{ ---- headless self-test (build with EXPORT_SELFTEST) ---- }
{$IFDEF EXPORT_SELFTEST}

type
  // test-only access to the plot's input handlers (same object, no new fields)
  TPlotDriver = class(TRho3DPlot)
  public
    procedure Down(AButton: TMouseButton; AShift: TShiftState; const P: TPointF);
    procedure MoveTo(AShift: TShiftState; const P: TPointF);
    procedure Up(AButton: TMouseButton; AShift: TShiftState; const P: TPointF);
    procedure Wheel(ADelta: Integer);
    procedure Key(AKey: Word; AChar: Char);
    procedure DoubleClick(ACtrl: Boolean);
  end;

procedure TPlotDriver.Down(AButton: TMouseButton; AShift: TShiftState; const P: TPointF);
begin
  MouseDown(AButton, AShift, P.X, P.Y);
end;

procedure TPlotDriver.MoveTo(AShift: TShiftState; const P: TPointF);
begin
  MouseMove(AShift, P.X, P.Y);
end;

procedure TPlotDriver.Up(AButton: TMouseButton; AShift: TShiftState; const P: TPointF);
begin
  MouseUp(AButton, AShift, P.X, P.Y);
end;

procedure TPlotDriver.Wheel(ADelta: Integer);
var
  h: Boolean;
begin
  h := False;
  MouseWheel([], ADelta, h);
end;

procedure TPlotDriver.Key(AKey: Word; AChar: Char);
var
  k: Word;
  c: WideChar;
begin
  k := AKey;
  c := AChar;
  KeyDown(k, c, []);
end;

procedure TPlotDriver.DoubleClick(ACtrl: Boolean);
begin
  if ACtrl then
    MouseDown(TMouseButton.mbLeft, [ssCtrl], 5, 5)
  else
    MouseDown(TMouseButton.mbLeft, [], 5, 5);
  MouseUp(TMouseButton.mbLeft, [], 5, 5);
  DblClick;
end;

procedure TfrmMain.RunSelfTest(Sender: TObject);
var
  dir: string;
  log: TStringList;

  function SameImages(const A, B: ISkImage; out ADiff: Integer): Boolean;
  var
    pa, pb: ISkPixmap;
    x, y: Integer;
    ra, rb: PCardinal;
  begin
    ADiff := 0;
    pa := A.PeekPixels;
    pb := B.PeekPixels;
    if (pa = nil) or (pb = nil) or (pa.Width <> pb.Width) or (pa.Height <> pb.Height) then
      Exit(False);
    for y := 0 to pa.Height - 1 do
    begin
      ra := pa.PixelAddr[0, y];
      rb := pb.PixelAddr[0, y];
      for x := 0 to pa.Width - 1 do
      begin
        if ra^ <> rb^ then
          Inc(ADiff);
        Inc(ra);
        Inc(rb);
      end;
    end;
    Result := ADiff = 0;
  end;

  procedure ExportScene(AMode: TDemoMode; const AName: string);
  var
    plot2: TRho3DPlot;
    img1, img2: ISkImage;
    diff: Integer;
  begin
    cmbMode.ItemIndex := Ord(AMode);
    Application.ProcessMessages;
    FPlot.SaveToPNG(TPath.Combine(dir, AName + '.png'), 1200, 900);
    FPlot.SaveToPDF(TPath.Combine(dir, AName + '.pdf'));
    FPlot.SavePlotToFile(TPath.Combine(dir, AName + '.json'));
    plot2 := TRho3DPlot.Create(nil);
    try
      plot2.Width := FPlot.Width;
      plot2.Height := FPlot.Height;
      plot2.LoadPlotFromFile(TPath.Combine(dir, AName + '.json'));
      plot2.SaveToPNG(TPath.Combine(dir, AName + '_reloaded.png'), 1200, 900);
      img1 := FPlot.MakeImage(1200, 900);
      img2 := plot2.MakeImage(1200, 900);
      if SameImages(img1, img2, diff) then
        log.Add(Format('%-14s export PNG/PDF/JSON ok; reload identical', [AName]))
      else
        log.Add(Format('%-14s export ok; RELOAD DIFFERS in %d pixels', [AName, diff]));
    finally
      plot2.Free;
    end;
  end;

  procedure Expect(ACond: Boolean; const AWhat: string);
  begin
    if ACond then
      log.Add('  ok    ' + AWhat)
    else
      log.Add('  FAIL  ' + AWhat);
  end;

  procedure Paint;
  begin
    FPlot.Repaint;
    Application.ProcessMessages;
  end;

  procedure Interact;
  var
    d: TPlotDriver;
    az, el, zm, px: Single;
    p, q: TPointF;
    dp: TRho3DDataPoint;
    i: Integer;
    ed: TCommonCustomForm;
  begin
    log.Add('Interaction:');
    d := TPlotDriver(FPlot);
    cmbMode.ItemIndex := Ord(dmCloud);
    FPlot.ResetView;
    Paint;
    // left-drag rotates: right decreases azimuth, down raises elevation
    az := FPlot.Azimuth; el := FPlot.Elevation;
    p := PointF(300, 300);
    d.Down(TMouseButton.mbLeft, [], p);
    for i := 1 to 10 do
      d.MoveTo([ssLeft], PointF(p.X + i * 4, p.Y + i * 2));
    Expect(FPlot.ReducedDetail, 'reduced detail while dragging');
    d.Up(TMouseButton.mbLeft, [], PointF(p.X + 40, p.Y + 20));
    Expect(not FPlot.ReducedDetail, 'full detail after release');
    Expect(SameValue(FPlot.Azimuth, az - 20, 0.01), Format('drag right: azimuth %.1f -> %.1f', [az, FPlot.Azimuth]));
    Expect(SameValue(FPlot.Elevation, el + 10, 0.01), Format('drag down: elevation %.1f -> %.1f', [el, FPlot.Elevation]));
    // elevation clamps at 90
    d.Down(TMouseButton.mbLeft, [], p);
    d.MoveTo([ssLeft], PointF(p.X, p.Y + 600));
    d.Up(TMouseButton.mbLeft, [], PointF(p.X, p.Y + 600));
    Expect(FPlot.Elevation = 90, 'elevation clamped to 90');
    // right-drag and shift-drag pan
    FPlot.ResetView;
    Paint;
    d.Down(TMouseButton.mbRight, [], p);
    d.MoveTo([ssRight], PointF(p.X + 61, p.Y));
    d.Up(TMouseButton.mbRight, [], PointF(p.X + 61, p.Y));
    px := FPlot.PanX;
    Expect(px > 0, Format('right-drag pans (PanX %.3f)', [px]));
    d.Down(TMouseButton.mbLeft, [ssShift], p);
    d.MoveTo([ssLeft, ssShift], PointF(p.X + 61, p.Y));
    d.Up(TMouseButton.mbLeft, [ssShift], PointF(p.X + 61, p.Y));
    Expect(SameValue(FPlot.PanX, 2 * px, 1E-4), 'shift-drag pans');
    // wheel zooms about the pointer: the data point under the cursor stays put
    FPlot.ResetView;
    Paint;
    dp := FPlot.Series[0].PointAt(10);
    FPlot.DataToScreen(dp.X, dp.Y, dp.Z, p);
    zm := FPlot.Zoom;
    d.MoveTo([], p);
    d.Wheel(120);
    Paint;
    FPlot.DataToScreen(dp.X, dp.Y, dp.Z, q);
    Expect(FPlot.Zoom > zm, 'wheel up zooms in');
    Expect(p.Distance(q) < 0.5, Format('zoom about pointer keeps the point fixed (moved %.2f px)', [p.Distance(q)]));
    // keys
    FPlot.ResetView;
    d.Key(0, '2');
    Expect((FPlot.Azimuth = 0) and (FPlot.Elevation = 90), 'key 2 = top view');
    d.Key(0, '1');
    Expect((FPlot.Azimuth = -60) and (FPlot.Elevation = 30), 'key 1 = isometric');
    d.Key(vkLeft, #0);
    Expect(FPlot.Azimuth = -55, 'left arrow rotates 5 degrees');
    d.Key(0, '+');
    Expect(FPlot.Zoom > 1, 'plus zooms in');
    d.Key(0, 'r');
    Expect((FPlot.Azimuth = -60) and (FPlot.Zoom = 1), 'R resets the view');
    // click on a point fires OnPointPicked with exact data values
    Paint;
    dp := FPlot.Series[0].PointAt(25);
    FPlot.DataToScreen(dp.X, dp.Y, dp.Z, p);
    lblInfo.Text := '';
    d.Down(TMouseButton.mbLeft, [], p);
    d.Up(TMouseButton.mbLeft, [], p);
    Expect(lblInfo.Text.StartsWith('Picked'), 'click picks a point: ' + lblInfo.Text);
    // legend: a click on the entry hides the series, again shows it
    Paint;
    p := PointF(FPlot.Width - 80 - 30, 30 + 10 + 7 + 9);   // colour bar on the right
    d.Down(TMouseButton.mbLeft, [], p);
    d.Up(TMouseButton.mbLeft, [], p);
    Expect(not FPlot.Series[0].Visible, 'legend click hides the series');
    Paint;
    d.Down(TMouseButton.mbLeft, [], p);
    d.Up(TMouseButton.mbLeft, [], p);
    Expect(FPlot.Series[0].Visible, 'second legend click shows it again');
    // dragging the legend moves it (and does not toggle)
    Paint;
    d.Down(TMouseButton.mbLeft, [], p);
    d.MoveTo([ssLeft], PointF(p.X - 100, p.Y + 50));
    d.Up(TMouseButton.mbLeft, [], PointF(p.X - 100, p.Y + 50));
    Expect(FPlot.Series[0].Visible, 'legend drag does not toggle');
    FPlot.SaveToPNG(TPath.Combine(dir, 'legend_dragged.png'), 900, 700);
    // double-click opens the editor, Ctrl+double-click resets the view
    FPlot.SetView(10, 10);
    d.DoubleClick(True);
    Expect(FPlot.Azimuth = -60, 'Ctrl+double-click resets the view');
    d.DoubleClick(False);
    Application.ProcessMessages;
    ed := nil;
    for i := 0 to Screen.FormCount - 1 do
      if Screen.Forms[i].ClassName = 'TRho3DPlotEditor' then
        ed := Screen.Forms[i];
    Expect((ed <> nil) and ed.Visible, 'double-click opens the property editor');
    if ed <> nil then
      ed.Close;
  end;

  procedure Bench(AMode: TDemoMode; const AName: string);
  const
    Frames = 20;
  var
    sw: TStopwatch;
    i: Integer;
    full, reduced: Double;
  begin
    cmbMode.ItemIndex := Ord(AMode);
    Application.ProcessMessages;
    FPlot.MakeImage;   // warm-up (prepare)
    sw := TStopwatch.StartNew;
    for i := 1 to Frames do
    begin
      FPlot.Azimuth := FPlot.Azimuth + 3;
      FPlot.MakeImage;
    end;
    full := sw.Elapsed.TotalMilliseconds / Frames;
    FPlot.ReducedDetail := True;
    sw := TStopwatch.StartNew;
    for i := 1 to Frames do
    begin
      FPlot.Azimuth := FPlot.Azimuth + 3;
      FPlot.MakeImage;
    end;
    reduced := sw.Elapsed.TotalMilliseconds / Frames;
    FPlot.ReducedDetail := False;
    log.Add(Format('%-14s %4.0f x %4.0f px: full %.1f ms/frame (%.0f fps), dragging %.1f ms/frame (%.0f fps)',
      [AName, FPlot.Width, FPlot.Height, full, 1000 / full, reduced, 1000 / reduced]));
  end;

var
  p: TRho3DViewPreset;
begin
  FSelfTestTimer.Enabled := False;
  dir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'selftest_out');
  ForceDirectories(dir);
  log := TStringList.Create;
  try
    try
      log.Add('Rho3DPlot self-test ' + DateTimeToStr(Now));
      log.Add(Format('Control %.0f x %.0f, scene scale %.2f',
        [FPlot.Width, FPlot.Height, FPlot.Scene.GetSceneScale]));
      ExportScene(dmLorenz, 'lorenz');
      ExportScene(dmSurface, 'surface');
      ExportScene(dmTorus, 'torus');
      ExportScene(dmCloud, 'cloud');
      ExportScene(dmSurfaceCurve, 'surface_curve');
      ExportScene(dmMobius, 'mobius');
      ExportScene(dmTraces, 'traces');
      // presets, orthographic, dark theme
      cmbMode.ItemIndex := Ord(dmSurface);
      for p := Low(TRho3DViewPreset) to High(TRho3DViewPreset) do
      begin
        FPlot.ViewPreset(p);
        FPlot.SaveToPNG(TPath.Combine(dir, 'view_' + ViewPresetNames[p] + '.png'), 900, 700);
      end;
      FPlot.ViewPreset(vpIsometric);
      FPlot.Projection := ppOrthographic;
      FPlot.SaveToPNG(TPath.Combine(dir, 'surface_ortho.png'), 900, 700);
      FPlot.Projection := ppPerspective;
      FPlot.Theme := thDark;
      cmbMode.ItemIndex := Ord(dmLorenz);
      FPlot.SaveToPNG(TPath.Combine(dir, 'lorenz_dark.png'), 900, 700);
      FPlot.SaveToPNG(TPath.Combine(dir, 'lorenz_transparent.png'), 900, 700, True);
      FPlot.RevealFraction := 0.4;
      FPlot.ShowRevealHead := True;
      FPlot.SaveToPNG(TPath.Combine(dir, 'lorenz_reveal40.png'), 900, 700);
      FPlot.Theme := thLight;
      ExportScene(dmBigSurface, 'big_surface');
      FPlot.SaveToPNG(TPath.Combine(dir, 'screen_scale.png'));   // on-screen size x scale
      Interact;
      Bench(dmBigCurve, 'curve 100k');
      Bench(dmBigSurface, 'surface 200^2');
      Bench(dmSurface, 'surface 61^2');
      Bench(dmLorenz, 'lorenz 8k');
      log.Add('DONE');
    except
      on E: Exception do
        log.Add('EXCEPTION: ' + E.ClassName + ': ' + E.Message);
    end;
    log.SaveToFile(TPath.Combine(dir, 'results.txt'));
  finally
    log.Free;
  end;
  Application.Terminate;
end;

{$ENDIF}

end.
