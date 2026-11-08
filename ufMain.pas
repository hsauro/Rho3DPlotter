unit ufMain;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  System.Math, System.Math.Vectors,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, System.Skia,
  FMX.Skia, FMX.Layouts, FMX.Controls.Presentation, FMX.StdCtrls, FMX.ListBox,
  Rho3DPlot;

type
  TDemoMode    = (dmLorenz, dmRossler, dmChua, dmTraces, dmCompare, dmStream, dmScatter);
  TStreamKind  = (skLorenz, skRossler, skChua);

  TfrmMain = class(TForm)
    Layout1: TLayout;
    Layout2: TLayout;
    btnReset: TButton;
    cmbMode: TComboBox;
    chkCube: TCheckBox;
    chkAxes: TCheckBox;
    chkGradient: TCheckBox;
    chkAutoRotate: TCheckBox;
    lblSpeed: TLabel;
    trkSpeed: TTrackBar;
    trkThickness: TTrackBar;
    cmbBackground: TComboBox;
    cmbSource: TComboBox;
    chkRolling: TCheckBox;
    cmbWindow: TComboBox;
    cmbDraw: TComboBox;
    chkDepth: TCheckBox;
    chkTransparent: TCheckBox;
    btnSavePng: TButton;
    btnSavePdf: TButton;
    lblHint: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure btnResetClick(Sender: TObject);
    procedure chkCubeChange(Sender: TObject);
    procedure chkAxesChange(Sender: TObject);
    procedure chkGradientChange(Sender: TObject);
    procedure chkAutoRotateChange(Sender: TObject);
    procedure trkSpeedChange(Sender: TObject);
    procedure chkDepthChange(Sender: TObject);
    procedure cmbModeChange(Sender: TObject);
    procedure trkThicknessChange(Sender: TObject);
    procedure cmbBackgroundChange(Sender: TObject);
    procedure cmbSourceChange(Sender: TObject);
    procedure chkRollingChange(Sender: TObject);
    procedure cmbWindowChange(Sender: TObject);
    procedure cmbDrawChange(Sender: TObject);
    procedure btnSavePngClick(Sender: TObject);
    procedure btnSavePdfClick(Sender: TObject);
  private
    FPlot: TRho3DPlot;
    // cached solutions
    FT, FX, FY, FZ: array of Double;        // Lorenz
    FRX, FRY, FRZ: array of Double;         // Rossler
    FCX, FCY, FCZ: array of Double;         // Chua
    FLMin, FLMax: TPoint3D;                 // Lorenz bounds
    FRMin, FRMax: TPoint3D;                 // Rossler bounds
    FCMin, FCMax: TPoint3D;                 // Chua bounds
    // live streaming state
    FTimer: TTimer;
    FStream: TRho3DSeries;
    FStreamKind: TStreamKind;
    FRolling: Boolean;
    FStreamWindow: Integer;
    FSx, FSy, FSz: Double;
    FStreamCount: Integer;
    FSyncingDraw: Boolean;
    procedure ComputeLorenz;
    procedure ComputeRossler;
    procedure ComputeChua;
    procedure StopStream;
    procedure ShowLorenz;
    procedure ShowRossler;
    procedure ShowChua;
    procedure ShowTraces;
    procedure ShowCompare;
    procedure ShowStream;
    procedure ShowScatter;
    procedure SetDrawMode(AIndex: Integer);
    procedure RunCurrentMode;
    procedure OnStreamTick(Sender: TObject);
  public
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.fmx}

const
  // Lorenz parameters
  L_sigma = 10.0;  L_rho = 28.0;  L_beta = 8.0 / 3.0;  L_dt = 0.005;
  // Rossler parameters
  R_a = 0.2;  R_b = 0.2;  R_c = 5.7;  R_dt = 0.02;
  // Chua's circuit parameters (double-scroll)
  C_alpha = 15.6;  C_beta = 28.0;  C_m0 = -1.143;  C_m1 = -0.714;  C_dt = 0.01;
  // streaming
  StreamMax    = 6000;   // non-rolling: stop after this many points
  // selectable rolling-window lengths (must match cmbWindow item order)
  WinSizes: array[0..4] of Integer = (500, 1000, 1500, 2500, 4000);

// Chua's piecewise-linear nonlinearity
function ChuaF(const x: Double): Double;
begin
  Result := C_m1 * x + 0.5 * (C_m0 - C_m1) * (Abs(x + 1) - Abs(x - 1));
end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FPlot := TRho3DPlot.Create(Self);
  FPlot.Parent := Self;
  FPlot.Align := TAlignLayout.Client;

  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 16;   // ~60 fps
  FTimer.OnTimer := OnStreamTick;

  ComputeLorenz;
  ComputeRossler;
  ComputeChua;

  cmbMode.ItemIndex := 0;
  cmbSource.ItemIndex := 0;
  cmbWindow.ItemIndex := 2;               // 1500
  cmbDraw.ItemIndex := 0;                 // Lines
  trkSpeed.Value := 30;
  FStreamWindow := WinSizes[cmbWindow.ItemIndex];
  RunCurrentMode;
end;

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

procedure TfrmMain.StopStream;
begin
  FTimer.Enabled := False;
  FStream := nil;
end;

// single Lorenz trajectory, coloured start -> end
procedure TfrmMain.ShowLorenz;
begin
  StopStream;
  FPlot.AutoScale;
  FPlot.AxisTitleX := 'X'; FPlot.AxisTitleY := 'Y'; FPlot.AxisTitleZ := 'Z';
  FPlot.SetPlotData(FX, FY, FZ);
  FPlot.Series[0].UseGradient := chkGradient.IsChecked;
  FPlot.Series[0].Thickness := trkThickness.Value;
end;

// single Rossler trajectory, coloured start -> end
procedure TfrmMain.ShowRossler;
begin
  StopStream;
  FPlot.AutoScale;
  FPlot.AxisTitleX := 'X'; FPlot.AxisTitleY := 'Y'; FPlot.AxisTitleZ := 'Z';
  FPlot.SetPlotData(FRX, FRY, FRZ);
  FPlot.Series[0].UseGradient := chkGradient.IsChecked;
  FPlot.Series[0].Thickness := trkThickness.Value;
end;

// single Chua trajectory (double-scroll), coloured start -> end
procedure TfrmMain.ShowChua;
begin
  StopStream;
  FPlot.AutoScale;
  FPlot.AxisTitleX := 'X'; FPlot.AxisTitleY := 'Y'; FPlot.AxisTitleZ := 'Z';
  FPlot.SetPlotData(FCX, FCY, FCZ);
  FPlot.Series[0].UseGradient := chkGradient.IsChecked;
  FPlot.Series[0].Thickness := trkThickness.Value;
end;

// x(t), y(t), z(t) staggered along Z (depth)
procedure TfrmMain.ShowTraces;
var
  s: TRho3DSeries;
  i, n: Integer;
begin
  StopStream;
  FPlot.AutoScale;
  FPlot.AxisTitleX := 'Time'; FPlot.AxisTitleY := 'Value'; FPlot.AxisTitleZ := 'Trace';
  FPlot.Clear;
  n := Length(FT);

  s := FPlot.AddSeries(TAlphaColors.Tomato);      s.Title := 'x(t)';
  s.Thickness := trkThickness.Value;
  for i := 0 to n - 1 do s.AddPoint(FT[i], FX[i], 0);

  s := FPlot.AddSeries(TAlphaColors.Limegreen);   s.Title := 'y(t)';
  s.Thickness := trkThickness.Value;
  for i := 0 to n - 1 do s.AddPoint(FT[i], FY[i], 1);

  s := FPlot.AddSeries(TAlphaColors.Deepskyblue); s.Title := 'z(t)';
  s.Thickness := trkThickness.Value;
  for i := 0 to n - 1 do s.AddPoint(FT[i], FZ[i], 2);
end;

// Lorenz and Rossler in the same cube for shape comparison
procedure TfrmMain.ShowCompare;
var
  s: TRho3DSeries;
  i: Integer;
begin
  StopStream;
  FPlot.AutoScale;
  FPlot.AxisTitleX := 'X'; FPlot.AxisTitleY := 'Y'; FPlot.AxisTitleZ := 'Z';
  FPlot.Clear;

  s := FPlot.AddSeries(TAlphaColors.Deepskyblue);  s.Title := 'Lorenz';
  s.Thickness := trkThickness.Value;
  for i := 0 to High(FX) do s.AddPoint(FX[i], FY[i], FZ[i]);

  s := FPlot.AddSeries(TAlphaColors.Orange);       s.Title := 'Rossler';
  s.Thickness := trkThickness.Value;
  for i := 0 to High(FRX) do s.AddPoint(FRX[i], FRY[i], FRZ[i]);
end;

// live streaming of the selected attractor (optionally a rolling window)
procedure TfrmMain.ShowStream;
begin
  StopStream;
  FStreamKind := TStreamKind(cmbSource.ItemIndex);
  FRolling := chkRolling.IsChecked;

  FPlot.AxisTitleX := 'X'; FPlot.AxisTitleY := 'Y'; FPlot.AxisTitleZ := 'Z';
  FPlot.Clear;

  // freeze the frame to the chosen attractor's full extent so it can't rescale
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

  FStream := FPlot.AddSeries;
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
    FStream.AddPoint(FSx, FSy, FSz);
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
    FTimer.Enabled := False;   // attractor fully drawn
end;

// a small data set (3D helix, ~16 points) to show markers with / without lines
procedure TfrmMain.ShowScatter;
const
  N = 16;
var
  s: TRho3DSeries;
  i: Integer;
  t: Double;
begin
  StopStream;
  FPlot.AutoScale;
  FPlot.AxisTitleX := 'X'; FPlot.AxisTitleY := 'Y'; FPlot.AxisTitleZ := 'Z';
  FPlot.Clear;
  s := FPlot.AddSeries(TAlphaColors.Deepskyblue);
  s.Thickness := trkThickness.Value;
  s.PointSize := 9;
  for i := 0 to N - 1 do
  begin
    t := i / (N - 1) * 4 * Pi;
    s.AddPoint(Cos(t), Sin(t), i);
  end;
end;

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
    dmLorenz:  ShowLorenz;
    dmRossler: ShowRossler;
    dmChua:    ShowChua;
    dmTraces:  ShowTraces;
    dmCompare: ShowCompare;
    dmStream:  ShowStream;
    dmScatter: ShowScatter;
  end;
  // sensible default per mode: scatter shows markers, everything else lines
  if mode = dmScatter then
    SetDrawMode(2)
  else
    SetDrawMode(0);
end;

procedure TfrmMain.cmbModeChange(Sender: TObject);
begin
  RunCurrentMode;
end;

// changing the stream source / rolling option restarts the stream if active
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

procedure TfrmMain.btnResetClick(Sender: TObject);
begin
  FPlot.ResetView;
end;

procedure TfrmMain.chkCubeChange(Sender: TObject);
begin
  FPlot.ShowCube := chkCube.IsChecked;
end;

procedure TfrmMain.chkAxesChange(Sender: TObject);
begin
  FPlot.ShowAxes := chkAxes.IsChecked;
end;

procedure TfrmMain.chkGradientChange(Sender: TObject);
begin
  // master: apply to every series currently shown
  FPlot.UseGradient := chkGradient.IsChecked;
end;

procedure TfrmMain.chkAutoRotateChange(Sender: TObject);
begin
  FPlot.AutoRotate := chkAutoRotate.IsChecked;
end;

procedure TfrmMain.trkSpeedChange(Sender: TObject);
begin
  FPlot.AutoRotateSpeed := trkSpeed.Value;   // degrees / second (may be negative)
end;

procedure TfrmMain.chkDepthChange(Sender: TObject);
begin
  FPlot.DepthCue := chkDepth.IsChecked;
end;

procedure TfrmMain.cmbDrawChange(Sender: TObject);
begin
  if FSyncingDraw then   // programmatic sync, not a user action
    Exit;
  SetDrawMode(cmbDraw.ItemIndex);
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
      // render at 2x on-screen size for a crisp raster
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
      FPlot.SaveToPDF(dlg.FileName);   // vector, page = on-screen size in points
  finally
    dlg.Free;
  end;
end;

procedure TfrmMain.cmbWindowChange(Sender: TObject);
begin
  // takes effect on the next tick; no need to restart the stream
  FStreamWindow := WinSizes[cmbWindow.ItemIndex];
end;

procedure TfrmMain.trkThicknessChange(Sender: TObject);
begin
  FPlot.LineThickness := trkThickness.Value;  // master: updates every series
end;

procedure TfrmMain.cmbBackgroundChange(Sender: TObject);
begin
  case cmbBackground.ItemIndex of
    0: begin  // Dark
         FPlot.BackgroundColor := $FF1A1A20;
         FPlot.AxisColor := TAlphaColors.Silver;
         FPlot.TextColor := TAlphaColors.Gainsboro;
         FPlot.CubeColor := $40FFFFFF;
       end;
    1: begin  // Light
         FPlot.BackgroundColor := TAlphaColors.White;
         FPlot.AxisColor := TAlphaColors.Dimgray;
         FPlot.TextColor := TAlphaColors.Black;
         FPlot.CubeColor := $30000000;
       end;
    2: begin  // Navy
         FPlot.BackgroundColor := $FF0B1E3A;
         FPlot.AxisColor := TAlphaColors.Lightsteelblue;
         FPlot.TextColor := TAlphaColors.White;
         FPlot.CubeColor := $40FFFFFF;
       end;
  end;
end;

end.
