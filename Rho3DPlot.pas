unit Rho3DPlot;

{
  TRho3DPlot - a Skia-based 3D line plotter for FMX.

  Plots one or more polylines through (x, y, z) data. Typical uses:

    * a single 3D trajectory (e.g. the Lorenz attractor), or
    * several traces staggered in depth (e.g. x(t), y(t), z(t) each drawn
      on its own plane along the Z axis).

  Each line is a TRho3DSeries and carries its own colour, thickness and
  optional start->end gradient. The bounding cube and axes are computed
  across every visible series so they share one coordinate frame.

  Mouse:
    Left drag ................ rotate (orbit)
    Right drag / Shift+drag .. pan
    Wheel .................... zoom

  Internally each axis is scaled independently so the combined data fills
  the unit cube [-1..1]^3.
}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.UITypes,
  System.Math,
  System.Math.Vectors,
  System.Generics.Collections,
  System.Skia,
  FMX.Types,
  FMX.Controls,
  FMX.Skia;

type
  TRho3DPlot = class;

  { A single 3D polyline with its own appearance. }
  TRho3DSeries = class
  private
    FOwner: TRho3DPlot;
    FPoints: TList<TPoint3D>;
    FColor: TAlphaColor;
    FGradientStartColor: TAlphaColor;
    FGradientEndColor: TAlphaColor;
    FThickness: Single;
    FUseGradient: Boolean;
    FVisible: Boolean;
    FShowLine: Boolean;
    FShowPoints: Boolean;
    FPointSize: Single;
    FTitle: string;
    procedure Changed;
    procedure SetColor(const Value: TAlphaColor);
    procedure SetGradientStartColor(const Value: TAlphaColor);
    procedure SetGradientEndColor(const Value: TAlphaColor);
    procedure SetThickness(const Value: Single);
    procedure SetUseGradient(const Value: Boolean);
    procedure SetVisible(const Value: Boolean);
    procedure SetShowLine(const Value: Boolean);
    procedure SetShowPoints(const Value: Boolean);
    procedure SetPointSize(const Value: Single);
    function GetCount: Integer;
  public
    constructor Create(AOwner: TRho3DPlot);
    destructor Destroy; override;
    procedure Clear;
    procedure AddPoint(const AX, AY, AZ: Double);
    procedure SetData(const AX, AY, AZ: array of Double); overload;
    procedure SetData(const APoints: array of TPoint3D); overload;
    property Points: TList<TPoint3D> read FPoints;
    property Count: Integer read GetCount;
    property Title: string read FTitle write FTitle;
    property Color: TAlphaColor read FColor write SetColor;
    property Thickness: Single read FThickness write SetThickness;
    property UseGradient: Boolean read FUseGradient write SetUseGradient;
    property GradientStartColor: TAlphaColor read FGradientStartColor write SetGradientStartColor;
    property GradientEndColor: TAlphaColor read FGradientEndColor write SetGradientEndColor;
    property Visible: Boolean read FVisible write SetVisible;
    /// draw the connecting polyline through the points
    property ShowLine: Boolean read FShowLine write SetShowLine;
    /// draw a filled marker at each data point (flat disc, not a 3D sphere)
    property ShowPoints: Boolean read FShowPoints write SetShowPoints;
    /// marker diameter in pixels
    property PointSize: Single read FPointSize write SetPointSize;
  end;

  TRho3DPlot = class(TSkCustomControl)
  public const
    DefaultLineColor       = TAlphaColors.Dodgerblue;
    DefaultCubeColor       = $40FFFFFF; // faint
    DefaultAxisColor       = TAlphaColors.Silver;
    DefaultTextColor       = TAlphaColors.Gainsboro;
    DefaultBackgroundColor = $FF1A1A20;
    DefaultGradientStart   = TAlphaColors.Deepskyblue;
    DefaultGradientEnd     = TAlphaColors.Orangered;
  strict private
    // data
    FSeries: TObjectList<TRho3DSeries>;
    FMin, FMax: TPoint3D;
    FBoundsValid: Boolean;
    FUseFixedBounds: Boolean;
    // view
    FYaw, FPitch: Single;     // radians
    FZoom: Single;
    FPanX, FPanY: Single;
    FDistance: Single;        // perspective camera distance
    // mouse
    FDragging: Boolean;
    FPanning: Boolean;
    FLastPos: TPointF;
    // appearance (cube / axes)
    FShowCube: Boolean;
    FShowAxes: Boolean;
    FShowTicks: Boolean;
    FShowValues: Boolean;
    FTickCount: Integer;
    FCubeColor: TAlphaColor;
    FAxisColor: TAlphaColor;
    FTextColor: TAlphaColor;
    FBackgroundColor: TAlphaColor;
    FAxisTitleX, FAxisTitleY, FAxisTitleZ: string;
    // default style applied to series created by SetPlotData / AddPoint,
    // and used as "master" controls that update every existing series.
    FLineColor: TAlphaColor;
    FLineThickness: Single;
    FUseGradient: Boolean;
    FGradientStartColor: TAlphaColor;
    FGradientEndColor: TAlphaColor;
    FShowLines: Boolean;
    FShowPoints: Boolean;
    FPointSize: Single;
    FDepthCue: Boolean;
    // auto-rotate
    FAutoRotate: Boolean;
    FAutoRotateSpeed: Single;   // degrees / second
    FRotateTimer: TTimer;
    procedure RotateTick(Sender: TObject);
    procedure EnsureBounds;
    function Normalize(const P: TPoint3D): TPoint3D;
    function Rotate(const P: TPoint3D): TPoint3D;
    function ProjectRotated(const R: TPoint3D; const ADest: TRectF): TPointF;
    function ProjectCube(const P: TPoint3D; const ADest: TRectF): TPointF;
    procedure DrawCube(const ACanvas: ISkCanvas; const ADest: TRectF);
    procedure DrawAxes(const ACanvas: ISkCanvas; const ADest: TRectF;
      const AFont: ISkFont);
    procedure DrawAllSeries(const ACanvas: ISkCanvas; const ADest: TRectF);
    procedure RenderScene(const ACanvas: ISkCanvas; const ADest: TRectF;
      const AClearColor: TAlphaColor);
    function GetSeries(Index: Integer): TRho3DSeries;
    function GetSeriesCount: Integer;
    function DefaultSeries: TRho3DSeries;
    procedure SetShowCube(const Value: Boolean);
    procedure SetShowAxes(const Value: Boolean);
    procedure SetShowTicks(const Value: Boolean);
    procedure SetShowValues(const Value: Boolean);
    procedure SetTickCount(const Value: Integer);
    procedure SetCubeColor(const Value: TAlphaColor);
    procedure SetAxisColor(const Value: TAlphaColor);
    procedure SetTextColor(const Value: TAlphaColor);
    procedure SetBackgroundColor(const Value: TAlphaColor);
    // master setters (propagate to all series)
    procedure SetLineColor(const Value: TAlphaColor);
    procedure SetLineThickness(const Value: Single);
    procedure SetUseGradient(const Value: Boolean);
    procedure SetGradientStartColor(const Value: TAlphaColor);
    procedure SetGradientEndColor(const Value: TAlphaColor);
    procedure SetShowLines(const Value: Boolean);
    procedure SetShowPoints(const Value: Boolean);
    procedure SetPointSize(const Value: Single);
    procedure SetDepthCue(const Value: Boolean);
    procedure SetAutoRotate(const Value: Boolean);
    procedure SetAutoRotateSpeed(const Value: Single);
  strict protected
    procedure Draw(const ACanvas: ISkCanvas; const ADest: TRectF;
      const AOpacity: Single); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Single); override;
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer;
      var Handled: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// Create a new empty series (styled from the current defaults).
    function AddSeries: TRho3DSeries; overload;
    function AddSeries(const AColor: TAlphaColor): TRho3DSeries; overload;
    /// Replace all data with a single series holding the given x/y/z columns.
    procedure SetPlotData(const AX, AY, AZ: array of Double); overload;
    procedure SetPlotData(const APoints: array of TPoint3D); overload;
    /// Append a point to the first (default) series, creating it if needed.
    procedure AddPoint(const AX, AY, AZ: Double);
    /// Remove every series.
    procedure Clear;
    /// Called by a series when its data or appearance changes.
    procedure SeriesChanged;
    /// Freeze the coordinate frame to the given data range. Useful while
    /// streaming so the plot does not rescale as points arrive.
    procedure SetDataBounds(const AMin, AMax: TPoint3D);
    /// Resume automatic scaling to fit the data.
    procedure AutoScale;
    /// Return the view to its default rotation / zoom / pan.
    procedure ResetView;
    /// Save the current view as a raster PNG. Pass 0 for AWidth/AHeight to use
    /// the control's on-screen size; larger values give a higher-resolution image.
    /// Set ATransparent to omit the background fill (a cut-out image with alpha).
    procedure SaveToPNG(const AFileName: string; AWidth: Integer = 0;
      AHeight: Integer = 0; ATransparent: Boolean = False);
    /// Save the current view as a vector PDF (scalable - ideal for publications).
    procedure SaveToPDF(const AFileName: string; AWidth: Integer = 0;
      AHeight: Integer = 0);
    property SeriesCount: Integer read GetSeriesCount;
    property Series[Index: Integer]: TRho3DSeries read GetSeries;
  published
    property ShowCube: Boolean read FShowCube write SetShowCube default True;
    property ShowAxes: Boolean read FShowAxes write SetShowAxes default True;
    property ShowTicks: Boolean read FShowTicks write SetShowTicks default True;
    property ShowValues: Boolean read FShowValues write SetShowValues default True;
    property TickCount: Integer read FTickCount write SetTickCount default 5;
    property CubeColor: TAlphaColor read FCubeColor write SetCubeColor default DefaultCubeColor;
    property AxisColor: TAlphaColor read FAxisColor write SetAxisColor default DefaultAxisColor;
    property TextColor: TAlphaColor read FTextColor write SetTextColor default DefaultTextColor;
    property BackgroundColor: TAlphaColor read FBackgroundColor write SetBackgroundColor default DefaultBackgroundColor;
    property AxisTitleX: string read FAxisTitleX write FAxisTitleX;
    property AxisTitleY: string read FAxisTitleY write FAxisTitleY;
    property AxisTitleZ: string read FAxisTitleZ write FAxisTitleZ;
    // master line style (applies to all series)
    property LineColor: TAlphaColor read FLineColor write SetLineColor default DefaultLineColor;
    property LineThickness: Single read FLineThickness write SetLineThickness;
    property UseGradient: Boolean read FUseGradient write SetUseGradient default True;
    property GradientStartColor: TAlphaColor read FGradientStartColor write SetGradientStartColor default DefaultGradientStart;
    property GradientEndColor: TAlphaColor read FGradientEndColor write SetGradientEndColor default DefaultGradientEnd;
    property ShowLines: Boolean read FShowLines write SetShowLines default True;
    property ShowPoints: Boolean read FShowPoints write SetShowPoints default False;
    property PointSize: Single read FPointSize write SetPointSize;
    /// fade markers toward the background with distance (a flat 3D depth cue)
    property DepthCue: Boolean read FDepthCue write SetDepthCue default False;
    property AutoRotate: Boolean read FAutoRotate write SetAutoRotate default False;
    property AutoRotateSpeed: Single read FAutoRotateSpeed write SetAutoRotateSpeed;

    property Align;
    property Anchors;
    property Height;
    property Width;
    property Position;
    property Size;
    property Visible;
    property HitTest;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
  end;

procedure Register;

implementation

const
  DegToRadf = Pi / 180;

{ ---- corner / edge tables for the unit cube [-1..1]^3 ---- }
const
  CubeCorners: array[0..7] of TPoint3D = (
    (X: -1; Y: -1; Z: -1),   // 0
    (X:  1; Y: -1; Z: -1),   // 1
    (X:  1; Y:  1; Z: -1),   // 2
    (X: -1; Y:  1; Z: -1),   // 3
    (X: -1; Y: -1; Z:  1),   // 4
    (X:  1; Y: -1; Z:  1),   // 5
    (X:  1; Y:  1; Z:  1),   // 6
    (X: -1; Y:  1; Z:  1));  // 7

  CubeEdges: array[0..11, 0..1] of Integer = (
    (0, 1), (1, 2), (2, 3), (3, 0),   // bottom face
    (4, 5), (5, 6), (6, 7), (7, 4),   // top face
    (0, 4), (1, 5), (2, 6), (3, 7));  // verticals

function LerpColor(const A, B: TAlphaColor; const T: Single): TAlphaColor;
var
  ra, ga, ba, aa: Byte;
  rb, gb, bb, ab: Byte;
  u: Single;
begin
  u := EnsureRange(T, 0, 1);
  aa := TAlphaColorRec(A).A; ra := TAlphaColorRec(A).R;
  ga := TAlphaColorRec(A).G; ba := TAlphaColorRec(A).B;
  ab := TAlphaColorRec(B).A; rb := TAlphaColorRec(B).R;
  gb := TAlphaColorRec(B).G; bb := TAlphaColorRec(B).B;
  TAlphaColorRec(Result).A := Round(aa + (ab - aa) * u);
  TAlphaColorRec(Result).R := Round(ra + (rb - ra) * u);
  TAlphaColorRec(Result).G := Round(ga + (gb - ga) * u);
  TAlphaColorRec(Result).B := Round(ba + (bb - ba) * u);
end;

{ TRho3DSeries }

constructor TRho3DSeries.Create(AOwner: TRho3DPlot);
begin
  inherited Create;
  FOwner := AOwner;
  FPoints := TList<TPoint3D>.Create;
  FVisible := True;
  FThickness := 1.5;
  FColor := TRho3DPlot.DefaultLineColor;
  FUseGradient := True;
  FGradientStartColor := TRho3DPlot.DefaultGradientStart;
  FGradientEndColor := TRho3DPlot.DefaultGradientEnd;
  FShowLine := True;
  FShowPoints := False;
  FPointSize := 6;
end;

destructor TRho3DSeries.Destroy;
begin
  FPoints.Free;
  inherited;
end;

procedure TRho3DSeries.Changed;
begin
  if FOwner <> nil then
    FOwner.SeriesChanged;
end;

function TRho3DSeries.GetCount: Integer;
begin
  Result := FPoints.Count;
end;

procedure TRho3DSeries.Clear;
begin
  FPoints.Clear;
  Changed;
end;

procedure TRho3DSeries.AddPoint(const AX, AY, AZ: Double);
begin
  FPoints.Add(TPoint3D.Create(AX, AY, AZ));
  Changed;
end;

procedure TRho3DSeries.SetData(const AX, AY, AZ: array of Double);
var
  i, n: Integer;
begin
  FPoints.Clear;
  n := Length(AX);
  if Length(AY) < n then n := Length(AY);
  if Length(AZ) < n then n := Length(AZ);
  FPoints.Capacity := n;
  for i := 0 to n - 1 do
    FPoints.Add(TPoint3D.Create(AX[i], AY[i], AZ[i]));
  Changed;
end;

procedure TRho3DSeries.SetData(const APoints: array of TPoint3D);
var
  i: Integer;
begin
  FPoints.Clear;
  FPoints.Capacity := Length(APoints);
  for i := 0 to High(APoints) do
    FPoints.Add(APoints[i]);
  Changed;
end;

procedure TRho3DSeries.SetColor(const Value: TAlphaColor);
begin
  if FColor <> Value then begin FColor := Value; Changed; end;
end;

procedure TRho3DSeries.SetGradientStartColor(const Value: TAlphaColor);
begin
  if FGradientStartColor <> Value then begin FGradientStartColor := Value; Changed; end;
end;

procedure TRho3DSeries.SetGradientEndColor(const Value: TAlphaColor);
begin
  if FGradientEndColor <> Value then begin FGradientEndColor := Value; Changed; end;
end;

procedure TRho3DSeries.SetThickness(const Value: Single);
begin
  if FThickness <> Value then begin FThickness := Value; Changed; end;
end;

procedure TRho3DSeries.SetUseGradient(const Value: Boolean);
begin
  if FUseGradient <> Value then begin FUseGradient := Value; Changed; end;
end;

procedure TRho3DSeries.SetVisible(const Value: Boolean);
begin
  if FVisible <> Value then begin FVisible := Value; Changed; end;
end;

procedure TRho3DSeries.SetShowLine(const Value: Boolean);
begin
  if FShowLine <> Value then begin FShowLine := Value; Changed; end;
end;

procedure TRho3DSeries.SetShowPoints(const Value: Boolean);
begin
  if FShowPoints <> Value then begin FShowPoints := Value; Changed; end;
end;

procedure TRho3DSeries.SetPointSize(const Value: Single);
begin
  if FPointSize <> Value then begin FPointSize := Value; Changed; end;
end;

{ TRho3DPlot }

constructor TRho3DPlot.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSeries := TObjectList<TRho3DSeries>.Create(True);
  HitTest := True;
  AutoCapture := True;
  FShowCube := True;
  FShowAxes := True;
  FShowTicks := True;
  FShowValues := True;
  FTickCount := 5;
  FCubeColor := DefaultCubeColor;
  FAxisColor := DefaultAxisColor;
  FTextColor := DefaultTextColor;
  FBackgroundColor := DefaultBackgroundColor;
  FLineColor := DefaultLineColor;
  FLineThickness := 1.5;
  FUseGradient := True;
  FGradientStartColor := DefaultGradientStart;
  FGradientEndColor := DefaultGradientEnd;
  FShowLines := True;
  FShowPoints := False;
  FPointSize := 6;
  FDepthCue := False;
  FAutoRotateSpeed := 30;   // degrees / second
  FAxisTitleX := 'X';
  FAxisTitleY := 'Y';
  FAxisTitleZ := 'Z';
  FDistance := 6;

  FRotateTimer := TTimer.Create(Self);
  FRotateTimer.Enabled := False;
  FRotateTimer.Interval := 16;   // ~60 fps
  FRotateTimer.OnTimer := RotateTick;

  ResetView;
end;

destructor TRho3DPlot.Destroy;
begin
  if FRotateTimer <> nil then
    FRotateTimer.Enabled := False;
  FSeries.Free;
  inherited;
end;

procedure TRho3DPlot.RotateTick(Sender: TObject);
begin
  // don't fight the user while they are dragging
  if FDragging then
    Exit;
  FYaw := FYaw + FAutoRotateSpeed * DegToRadf * (FRotateTimer.Interval / 1000);
  if FYaw > Pi then
    FYaw := FYaw - 2 * Pi
  else if FYaw < -Pi then
    FYaw := FYaw + 2 * Pi;
  Redraw;
end;

procedure TRho3DPlot.ResetView;
begin
  FYaw := -35 * DegToRadf;
  FPitch := 25 * DegToRadf;
  FZoom := 1;
  FPanX := 0;
  FPanY := 0;
  Redraw;
end;

procedure TRho3DPlot.SaveToPNG(const AFileName: string; AWidth, AHeight: Integer;
  ATransparent: Boolean);
var
  surface: ISkSurface;
  image: ISkImage;
  clear: TAlphaColor;
begin
  if AWidth <= 0 then AWidth := Round(Width);
  if AHeight <= 0 then AHeight := Round(Height);
  if (AWidth <= 0) or (AHeight <= 0) then
    raise Exception.Create('SaveToPNG: invalid image size');

  if ATransparent then
    clear := TAlphaColors.Null      // fully transparent backdrop
  else
    clear := FBackgroundColor;

  surface := TSkSurface.MakeRaster(AWidth, AHeight);
  RenderScene(surface.Canvas, TRectF.Create(0, 0, AWidth, AHeight), clear);
  image := surface.MakeImageSnapshot;
  image.EncodeToFile(AFileName, TSkEncodedImageFormat.PNG);
end;

procedure TRho3DPlot.SaveToPDF(const AFileName: string; AWidth, AHeight: Integer);
var
  stream: TFileStream;
  document: ISkDocument;
  canvas: ISkCanvas;
  metadata: TSkPDFMetadata;
begin
  if AWidth <= 0 then AWidth := Round(Width);
  if AHeight <= 0 then AHeight := Round(Height);
  if (AWidth <= 0) or (AHeight <= 0) then
    raise Exception.Create('SaveToPDF: invalid page size');

  stream := TFileStream.Create(AFileName, fmCreate);
  try
    metadata := TSkPDFMetadata.Create('3D Plot', '', '', '', 'TRho3DPlot');
    document := TSkDocument.MakePDF(stream, metadata);
    try
      // one page, drawn as vector graphics (points are 1/72")
      canvas := document.BeginPage(AWidth, AHeight);
      RenderScene(canvas, TRectF.Create(0, 0, AWidth, AHeight), FBackgroundColor);
      document.EndPage;
    finally
      document.Close;
    end;
  finally
    stream.Free;
  end;
end;

function TRho3DPlot.GetSeriesCount: Integer;
begin
  Result := FSeries.Count;
end;

function TRho3DPlot.GetSeries(Index: Integer): TRho3DSeries;
begin
  Result := FSeries[Index];
end;

function TRho3DPlot.AddSeries: TRho3DSeries;
begin
  Result := TRho3DSeries.Create(Self);
  Result.FColor := FLineColor;
  Result.FThickness := FLineThickness;
  Result.FUseGradient := FUseGradient;
  Result.FGradientStartColor := FGradientStartColor;
  Result.FGradientEndColor := FGradientEndColor;
  Result.FShowLine := FShowLines;
  Result.FShowPoints := FShowPoints;
  Result.FPointSize := FPointSize;
  FSeries.Add(Result);
  SeriesChanged;
end;

function TRho3DPlot.AddSeries(const AColor: TAlphaColor): TRho3DSeries;
begin
  Result := AddSeries;
  Result.FColor := AColor;
  Result.FUseGradient := False;
end;

function TRho3DPlot.DefaultSeries: TRho3DSeries;
begin
  if FSeries.Count = 0 then
    AddSeries;
  Result := FSeries[0];
end;

procedure TRho3DPlot.SetPlotData(const AX, AY, AZ: array of Double);
begin
  FSeries.Clear;
  AddSeries.SetData(AX, AY, AZ);
end;

procedure TRho3DPlot.SetPlotData(const APoints: array of TPoint3D);
begin
  FSeries.Clear;
  AddSeries.SetData(APoints);
end;

procedure TRho3DPlot.AddPoint(const AX, AY, AZ: Double);
begin
  DefaultSeries.AddPoint(AX, AY, AZ);
end;

procedure TRho3DPlot.Clear;
begin
  FSeries.Clear;
  SeriesChanged;
end;

procedure TRho3DPlot.SeriesChanged;
begin
  if not FUseFixedBounds then
    FBoundsValid := False;
  Redraw;
end;

procedure TRho3DPlot.SetDataBounds(const AMin, AMax: TPoint3D);
begin
  FMin := AMin;
  FMax := AMax;
  FUseFixedBounds := True;
  FBoundsValid := True;
  Redraw;
end;

procedure TRho3DPlot.AutoScale;
begin
  FUseFixedBounds := False;
  FBoundsValid := False;
  Redraw;
end;

procedure TRho3DPlot.EnsureBounds;
var
  s: TRho3DSeries;
  i: Integer;
  P: TPoint3D;
  first: Boolean;
begin
  if FBoundsValid or FUseFixedBounds then
    Exit;
  first := True;
  for s in FSeries do
  begin
    if not s.Visible then
      Continue;
    for i := 0 to s.FPoints.Count - 1 do
    begin
      P := s.FPoints[i];
      if first then
      begin
        FMin := P; FMax := P;
        first := False;
      end
      else
      begin
        FMin.X := Min(FMin.X, P.X); FMax.X := Max(FMax.X, P.X);
        FMin.Y := Min(FMin.Y, P.Y); FMax.Y := Max(FMax.Y, P.Y);
        FMin.Z := Min(FMin.Z, P.Z); FMax.Z := Max(FMax.Z, P.Z);
      end;
    end;
  end;
  if first then
  begin
    FMin := TPoint3D.Create(-1, -1, -1);
    FMax := TPoint3D.Create(1, 1, 1);
  end;
  FBoundsValid := True;
end;

// map a data point into the [-1..1] cube (each axis scaled independently)
function TRho3DPlot.Normalize(const P: TPoint3D): TPoint3D;

  function Map(const V, Lo, Hi: Single): Single;
  var
    r: Single;
  begin
    r := Hi - Lo;
    if r < 1E-12 then
      Exit(0);
    Result := 2 * (V - Lo) / r - 1;
  end;

begin
  Result.X := Map(P.X, FMin.X, FMax.X);
  Result.Y := Map(P.Y, FMin.Y, FMax.Y);
  Result.Z := Map(P.Z, FMin.Z, FMax.Z);
end;

// rotate a cube-space point by the current yaw (about Y) then pitch (about X)
function TRho3DPlot.Rotate(const P: TPoint3D): TPoint3D;
var
  cy, sy, cx, sx: Single;
  x1, y1, z1: Single;
begin
  cy := Cos(FYaw);  sy := Sin(FYaw);
  cx := Cos(FPitch); sx := Sin(FPitch);
  // yaw about Y
  x1 := P.X * cy - P.Z * sy;
  z1 := P.X * sy + P.Z * cy;
  y1 := P.Y;
  // pitch about X
  Result.X := x1;
  Result.Y := y1 * cx - z1 * sx;
  Result.Z := y1 * sx + z1 * cx;
end;

// project an already-rotated cube-space point to screen coordinates.
// R.Z is the view-space depth (larger = nearer the camera).
function TRho3DPlot.ProjectRotated(const R: TPoint3D; const ADest: TRectF): TPointF;
var
  persp, baseScale, cx, cyy: Single;
begin
  persp := FDistance / (FDistance - R.Z);
  baseScale := Min(ADest.Width, ADest.Height) * 0.40 * FZoom;
  cx := ADest.Left + ADest.Width / 2;
  cyy := ADest.Top + ADest.Height / 2;
  Result.X := cx + FPanX + R.X * baseScale * persp;
  Result.Y := cyy + FPanY - R.Y * baseScale * persp;
end;

// project a cube-space point ([-1..1]) to screen coordinates
function TRho3DPlot.ProjectCube(const P: TPoint3D; const ADest: TRectF): TPointF;
begin
  Result := ProjectRotated(Rotate(P), ADest);
end;

procedure TRho3DPlot.DrawCube(const ACanvas: ISkCanvas; const ADest: TRectF);
var
  paint: ISkPaint;
  i: Integer;
  p1, p2: TPointF;
begin
  paint := TSkPaint.Create(TSkPaintStyle.Stroke);
  paint.AntiAlias := True;
  paint.Color := FCubeColor;
  paint.StrokeWidth := 1;
  for i := 0 to High(CubeEdges) do
  begin
    p1 := ProjectCube(CubeCorners[CubeEdges[i][0]], ADest);
    p2 := ProjectCube(CubeCorners[CubeEdges[i][1]], ADest);
    ACanvas.DrawLine(p1, p2, paint);
  end;
end;

procedure TRho3DPlot.DrawAxes(const ACanvas: ISkCanvas; const ADest: TRectF;
  const AFont: ISkFont);
var
  axisPaint, textPaint: ISkPaint;

  procedure DrawOneAxis(const AStart, AEnd, ATickDir: TPoint3D;
    const ADataLo, ADataHi: Single; const ATitle: string);
  var
    j: Integer;
    t, val: Single;
    a, b, tickBase, tickEnd, lblPos: TPoint3D;
    lp: TPointF;
    s: string;
  begin
    a := AStart;
    b := AEnd;
    ACanvas.DrawLine(ProjectCube(a, ADest), ProjectCube(b, ADest), axisPaint);

    if not FShowTicks then
      Exit;

    for j := 0 to FTickCount do
    begin
      t := j / FTickCount;                 // 0..1 along the axis
      tickBase := a + (b - a) * t;
      tickEnd := tickBase + ATickDir * 0.06;
      ACanvas.DrawLine(ProjectCube(tickBase, ADest),
        ProjectCube(tickEnd, ADest), axisPaint);

      if FShowValues then
      begin
        val := ADataLo + (ADataHi - ADataLo) * t;
        s := Format('%.4g', [val]);
        lblPos := tickBase + ATickDir * 0.16;
        lp := ProjectCube(lblPos, ADest);
        ACanvas.DrawSimpleText(s, lp.X - AFont.MeasureText(s) / 2,
          lp.Y + AFont.Size / 2, AFont, textPaint);
      end;
    end;

    // axis title at the far end
    lblPos := b + ATickDir * 0.30;
    lp := ProjectCube(lblPos, ADest);
    ACanvas.DrawSimpleText(ATitle, lp.X - AFont.MeasureText(ATitle) / 2,
      lp.Y + AFont.Size / 2, AFont, textPaint);
  end;

begin
  axisPaint := TSkPaint.Create(TSkPaintStyle.Stroke);
  axisPaint.AntiAlias := True;
  axisPaint.Color := FAxisColor;
  axisPaint.StrokeWidth := 1.5;

  textPaint := TSkPaint.Create(TSkPaintStyle.Fill);
  textPaint.AntiAlias := True;
  textPaint.Color := FTextColor;

  EnsureBounds;
  // X axis: corner 0 -> 1, ticks pushed toward -Z
  DrawOneAxis(CubeCorners[0], CubeCorners[1],
    TPoint3D.Create(0, 0, -1), FMin.X, FMax.X, FAxisTitleX);
  // Y axis: corner 0 -> 3, ticks pushed toward -X
  DrawOneAxis(CubeCorners[0], CubeCorners[3],
    TPoint3D.Create(-1, 0, 0), FMin.Y, FMax.Y, FAxisTitleY);
  // Z axis: corner 0 -> 4, ticks pushed toward -X
  DrawOneAxis(CubeCorners[0], CubeCorners[4],
    TPoint3D.Create(-1, 0, 0), FMin.Z, FMax.Z, FAxisTitleZ);
end;

procedure TRho3DPlot.DrawAllSeries(const ACanvas: ISkCanvas; const ADest: TRectF);

  function PointColor(const s: TRho3DSeries; const AIndex, ACount: Integer): TAlphaColor;
  begin
    if s.FUseGradient and (ACount > 1) then
      Result := LerpColor(s.FGradientStartColor, s.FGradientEndColor,
        AIndex / (ACount - 1))
    else
      Result := s.FColor;
  end;

var
  s: TRho3DSeries;
  i, n: Integer;
  pts: TArray<TPointF>;
  depths: TArray<Single>;
  dmin, dmax, fade: Single;
  r: TPoint3D;
  linePaint, fillPaint: ISkPaint;
  col: TAlphaColor;
begin
  for s in FSeries do
  begin
    if (not s.Visible) or (s.FPoints.Count < 1) then
      Continue;

    n := s.FPoints.Count;
    SetLength(pts, n);
    SetLength(depths, n);
    dmin := MaxSingle; dmax := -MaxSingle;
    for i := 0 to n - 1 do
    begin
      r := Rotate(Normalize(s.FPoints[i]));
      pts[i] := ProjectRotated(r, ADest);
      depths[i] := r.Z;                 // larger = nearer the camera
      dmin := Min(dmin, r.Z); dmax := Max(dmax, r.Z);
    end;

    // connecting polyline
    if s.FShowLine and (n >= 2) then
    begin
      linePaint := TSkPaint.Create(TSkPaintStyle.Stroke);
      linePaint.AntiAlias := True;
      linePaint.StrokeWidth := s.FThickness;
      if s.FUseGradient then
      begin
        for i := 0 to n - 2 do
        begin
          linePaint.Color := PointColor(s, i, n);
          ACanvas.DrawLine(pts[i], pts[i + 1], linePaint);
        end;
      end
      else
      begin
        linePaint.Color := s.FColor;
        ACanvas.DrawPoints(TSkDrawPointsMode.Polygon, pts, linePaint);
      end;
    end;

    // flat point markers
    if s.FShowPoints and (s.FPointSize > 0) then
    begin
      fillPaint := TSkPaint.Create(TSkPaintStyle.Fill);
      fillPaint.AntiAlias := True;
      for i := 0 to n - 1 do
      begin
        col := PointColor(s, i, n);
        if FDepthCue and (dmax > dmin) then
        begin
          // 0 at the nearest point, 1 at the farthest -> fade toward background
          fade := (dmax - depths[i]) / (dmax - dmin);
          col := LerpColor(col, FBackgroundColor, fade * 0.75);
        end;
        fillPaint.Color := col;
        ACanvas.DrawCircle(pts[i], s.FPointSize / 2, fillPaint);
      end;
    end;
  end;
end;

// Render the whole plot (background, cube, axes, series) onto any canvas at
// any size. Shared by on-screen painting and PNG / PDF export. AClearColor is
// the fill for the backdrop (pass a transparent colour for a cut-out PNG).
procedure TRho3DPlot.RenderScene(const ACanvas: ISkCanvas; const ADest: TRectF;
  const AClearColor: TAlphaColor);
var
  font: ISkFont;
begin
  ACanvas.Clear(AClearColor);

  // Make sure the coordinate frame is up to date regardless of which
  // decorations are visible (the series need it even with axes off).
  EnsureBounds;

  if FShowCube then
    DrawCube(ACanvas, ADest);

  if FShowAxes then
  begin
    font := TSkFont.Create(nil, 11);
    DrawAxes(ACanvas, ADest, font);
  end;

  DrawAllSeries(ACanvas, ADest);
end;

procedure TRho3DPlot.Draw(const ACanvas: ISkCanvas; const ADest: TRectF;
  const AOpacity: Single);
begin
  RenderScene(ACanvas, ADest, FBackgroundColor);
end;

{ ---- mouse interaction ---- }

procedure TRho3DPlot.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Single);
begin
  inherited;
  FLastPos := PointF(X, Y);
  if (Button = TMouseButton.mbRight) or
     ((Button = TMouseButton.mbLeft) and (ssShift in Shift)) then
    FPanning := True
  else if Button = TMouseButton.mbLeft then
    FDragging := True;
end;

procedure TRho3DPlot.MouseMove(Shift: TShiftState; X, Y: Single);
var
  dx, dy: Single;
begin
  inherited;
  if not (FDragging or FPanning) then
    Exit;
  dx := X - FLastPos.X;
  dy := Y - FLastPos.Y;
  FLastPos := PointF(X, Y);

  if FPanning then
  begin
    FPanX := FPanX + dx;
    FPanY := FPanY + dy;
  end
  else
  begin
    FYaw := FYaw + dx * 0.01;
    FPitch := FPitch + dy * 0.01;
    FPitch := EnsureRange(FPitch, -89 * DegToRadf, 89 * DegToRadf);
  end;
  Redraw;
end;

procedure TRho3DPlot.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Single);
begin
  inherited;
  FDragging := False;
  FPanning := False;
end;

procedure TRho3DPlot.MouseWheel(Shift: TShiftState; WheelDelta: Integer;
  var Handled: Boolean);
var
  factor: Single;
begin
  inherited;
  if WheelDelta > 0 then
    factor := 1.1
  else
    factor := 1 / 1.1;
  FZoom := EnsureRange(FZoom * factor, 0.05, 100);
  Handled := True;
  Redraw;
end;

{ ---- property setters ---- }

procedure TRho3DPlot.SetShowCube(const Value: Boolean);
begin
  if FShowCube <> Value then begin FShowCube := Value; Redraw; end;
end;

procedure TRho3DPlot.SetShowAxes(const Value: Boolean);
begin
  if FShowAxes <> Value then begin FShowAxes := Value; Redraw; end;
end;

procedure TRho3DPlot.SetShowTicks(const Value: Boolean);
begin
  if FShowTicks <> Value then begin FShowTicks := Value; Redraw; end;
end;

procedure TRho3DPlot.SetShowValues(const Value: Boolean);
begin
  if FShowValues <> Value then begin FShowValues := Value; Redraw; end;
end;

procedure TRho3DPlot.SetTickCount(const Value: Integer);
begin
  if (FTickCount <> Value) and (Value >= 1) then
  begin FTickCount := Value; Redraw; end;
end;

procedure TRho3DPlot.SetCubeColor(const Value: TAlphaColor);
begin
  if FCubeColor <> Value then begin FCubeColor := Value; Redraw; end;
end;

procedure TRho3DPlot.SetAxisColor(const Value: TAlphaColor);
begin
  if FAxisColor <> Value then begin FAxisColor := Value; Redraw; end;
end;

procedure TRho3DPlot.SetTextColor(const Value: TAlphaColor);
begin
  if FTextColor <> Value then begin FTextColor := Value; Redraw; end;
end;

procedure TRho3DPlot.SetBackgroundColor(const Value: TAlphaColor);
begin
  if FBackgroundColor <> Value then begin FBackgroundColor := Value; Redraw; end;
end;

procedure TRho3DPlot.SetLineColor(const Value: TAlphaColor);
var
  s: TRho3DSeries;
begin
  FLineColor := Value;
  for s in FSeries do
    s.FColor := Value;
  Redraw;
end;

procedure TRho3DPlot.SetLineThickness(const Value: Single);
var
  s: TRho3DSeries;
begin
  FLineThickness := Value;
  for s in FSeries do
    s.FThickness := Value;
  Redraw;
end;

procedure TRho3DPlot.SetUseGradient(const Value: Boolean);
var
  s: TRho3DSeries;
begin
  FUseGradient := Value;
  for s in FSeries do
    s.FUseGradient := Value;
  Redraw;
end;

procedure TRho3DPlot.SetGradientStartColor(const Value: TAlphaColor);
var
  s: TRho3DSeries;
begin
  FGradientStartColor := Value;
  for s in FSeries do
    s.FGradientStartColor := Value;
  Redraw;
end;

procedure TRho3DPlot.SetGradientEndColor(const Value: TAlphaColor);
var
  s: TRho3DSeries;
begin
  FGradientEndColor := Value;
  for s in FSeries do
    s.FGradientEndColor := Value;
  Redraw;
end;

procedure TRho3DPlot.SetShowLines(const Value: Boolean);
var
  s: TRho3DSeries;
begin
  FShowLines := Value;
  for s in FSeries do
    s.FShowLine := Value;
  Redraw;
end;

procedure TRho3DPlot.SetShowPoints(const Value: Boolean);
var
  s: TRho3DSeries;
begin
  FShowPoints := Value;
  for s in FSeries do
    s.FShowPoints := Value;
  Redraw;
end;

procedure TRho3DPlot.SetPointSize(const Value: Single);
var
  s: TRho3DSeries;
begin
  FPointSize := Value;
  for s in FSeries do
    s.FPointSize := Value;
  Redraw;
end;

procedure TRho3DPlot.SetDepthCue(const Value: Boolean);
begin
  if FDepthCue <> Value then begin FDepthCue := Value; Redraw; end;
end;

procedure TRho3DPlot.SetAutoRotate(const Value: Boolean);
begin
  if FAutoRotate <> Value then
  begin
    FAutoRotate := Value;
    FRotateTimer.Enabled := Value;
  end;
end;

procedure TRho3DPlot.SetAutoRotateSpeed(const Value: Single);
begin
  FAutoRotateSpeed := Value;
end;

procedure Register;
begin
  RegisterComponents('Rhody Controls', [TRho3DPlot]);
end;

end.
