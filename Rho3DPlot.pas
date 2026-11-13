unit Rho3DPlot;

{
  TRho3DPlot - a Skia-based 3D plotting control for FMX.

  Series kinds (any mix in one plot):
    * skCurve              polyline through (x, y, z); NaN lifts the pen
    * skScatter            markers at (x, y, z), optionally coloured by a value
    * skSurface            z = f(x, y) over a grid X[j], Y[i], Z[i][j]
    * skParametricSurface  matrices X[i][j], Y[i][j], Z[i][j] over a (u, v) grid
    * skBars               a bar at each grid point (X[j], Y[i]) from 0 to
                           Z[i][j] (down for negative heights)

  Rendering pipeline (see SPEC.md section 5):
    1. Prepare (on data / style change): data bounds, box shape (aspect),
       normalised points, per-point and per-face colours, face normals.
    2. Transform (every frame): rotate and project every point.
    3. Sort: faces, curve chunks and markers in one list, far to near.
    4. Draw: back panes / grid / box edges, the sorted drawables, front box
       edges, axes, colour bar, legend, title.
  RenderScene is the single render path for the screen and for PNG / PDF
  export, so exports match the screen.

  Mouse:  left-drag rotate, right-drag / Shift+drag pan, wheel zoom about the
          pointer, double-click property editor, Ctrl+double-click reset view,
          right-click (no drag) context menu, hover read-out, click picks.
  Keys:   arrows rotate 5 degrees, + / - zoom, R reset, 1-4 preset views.
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
  System.JSON,
  System.Diagnostics,
  System.Skia,
  FMX.Types,
  FMX.Controls,
  FMX.Menus,
  FMX.Skia,
  Rho3DTransform,
  Rho3DColorMaps;

type
  TRho3DSeriesKind = (skCurve, skScatter, skSurface, skParametricSurface, skBars);
  TRho3DFillMode   = (fmFilled, fmWireframe, fmFilledWithEdges);
  TRho3DMarker     = (mkCircle, mkSquare, mkDiamond, mkTriangle, mkCross);
  TRho3DViewPreset = (vpIsometric, vpTop, vpFront, vpSide);
  TRho3DTheme      = (thLight, thDark);
  TRho3DLegendLocation = (llTopRight, llTopLeft, llBottomRight, llBottomLeft);

  // re-exported so users only need "uses Rho3DPlot"
  TRho3DColorMap   = Rho3DColorMaps.TRho3DColorMap;
  TRho3DProjection = Rho3DTransform.TRho3DProjection;
  TRho3DAspect     = Rho3DTransform.TRho3DAspect;
  TRho3DMatrix     = TArray<TArray<Double>>;

  TRho3DDataPoint = record
    X, Y, Z: Double;
  end;

  /// One quad of a surface: corner indices into the series' vertex arrays.
  TRho3DFace = record
    I0, I1, I2, I3: Integer;
    Color: TAlphaColor;      // base colour (colour map or solid), before shading
    Normal: TPoint3D;        // unit normal in box space
  end;

const
  cmViridis = Rho3DColorMaps.cmViridis;
  cmPlasma  = Rho3DColorMaps.cmPlasma;
  cmCoolwarm = Rho3DColorMaps.cmCoolwarm;
  cmGray    = Rho3DColorMaps.cmGray;
  cmJet     = Rho3DColorMaps.cmJet;
  ppPerspective  = Rho3DTransform.ppPerspective;
  ppOrthographic = Rho3DTransform.ppOrthographic;
  asIndependent = Rho3DTransform.asIndependent;
  asEqual       = Rho3DTransform.asEqual;
  asCustom      = Rho3DTransform.asCustom;

type
  TRho3DPlot = class;
  TRho3DSeries = class;

  TRho3DPointPicked = procedure(Sender: TObject; ASeries: TRho3DSeries;
    AIndex: Integer; const AX, AY, AZ: Double) of object;

  { One data set (curve, scatter or surface) with its own appearance. }
  TRho3DSeries = class
  private
    // fields are private (not strict private) so the plot's master setters
    // and renderer can use them directly (same-unit friendship)
    FOwner: TRho3DPlot;
    FKind: TRho3DSeriesKind;
    FPoints: TList<TPoint3D>;
    FValues: TList<Double>;
    FRows, FCols: Integer;
    FGridX, FGridY: TArray<Double>;          // skSurface, skBars: X[j], Y[i]
    FSurfX, FSurfY, FSurfZ: TRho3DMatrix;    // surfaces and bars: [i][j]
    FSurfC: TRho3DMatrix;                    // optional colour values
    FBarWidth: Single;                       // skBars: fraction of the spacing
    FTitle: string;
    FColor: TAlphaColor;
    FGradientStartColor: TAlphaColor;
    FGradientEndColor: TAlphaColor;
    FThickness: Single;
    FUseGradient: Boolean;
    FVisible: Boolean;
    FShowInLegend: Boolean;
    FShowLine: Boolean;
    FShowPoints: Boolean;
    FPointSize: Single;
    FOpacity: Single;
    FColorMap: TRho3DColorMap;
    FColorByValue: Boolean;
    FMarkerShape: TRho3DMarker;
    FFillMode: TRho3DFillMode;
    FEdgeColor: TAlphaColor;
    FEdgeWidth: Single;
    FShaded: Boolean;
    // render cache, owned and filled by the plot
    FNorm: TArray<TPoint3D>;          // box-space positions (NaN = gap / hole)
    FPtColor: TArray<TAlphaColor>;    // per-point colour (curve / scatter)
    FFaces: TArray<TRho3DFace>;
    FCoarseFaces: TArray<TRho3DFace>; // reduced grid used while dragging
    FScr: TArray<TPointF>;            // projected positions (last render)
    FDepth: TArray<Single>;           // view depth, larger = nearer
    FDepthMin, FDepthMax: Single;
    FHeadScr: TPointF;
    FHeadDepth: Single;
    FHeadColor: TAlphaColor;
    FHeadValid: Boolean;
    procedure SetColor(const Value: TAlphaColor);
    procedure SetGradientStartColor(const Value: TAlphaColor);
    procedure SetGradientEndColor(const Value: TAlphaColor);
    procedure SetThickness(const Value: Single);
    procedure SetUseGradient(const Value: Boolean);
    procedure SetVisible(const Value: Boolean);
    procedure SetShowInLegend(const Value: Boolean);
    procedure SetShowLine(const Value: Boolean);
    procedure SetShowPoints(const Value: Boolean);
    procedure SetPointSize(const Value: Single);
    procedure SetOpacity(const Value: Single);
    procedure SetColorMap(const Value: TRho3DColorMap);
    procedure SetColorByValue(const Value: Boolean);
    procedure SetMarkerShape(const Value: TRho3DMarker);
    procedure SetFillMode(const Value: TRho3DFillMode);
    procedure SetEdgeColor(const Value: TAlphaColor);
    procedure SetEdgeWidth(const Value: Single);
    procedure SetShaded(const Value: Boolean);
    procedure SetKind(const Value: TRho3DSeriesKind);
    procedure SetTitle(const Value: string);
    procedure SetBarWidth(const Value: Single);
    procedure SetGrid(const X, Y: array of Double; const Z: TRho3DMatrix);
    function GetCount: Integer;
    function GetIsSurface: Boolean;
    function GetIsBars: Boolean;
    function ColorValueAt(AIndex: Integer): Double;
  public
    constructor Create(AOwner: TRho3DPlot);
    destructor Destroy; override;
    /// Tell the plot the data or style changed (call after editing Points
    /// directly).
    procedure Changed;
    procedure Clear;
    procedure AddPoint(const AX, AY, AZ: Double); overload;
    /// Append a point with a colour value (scatter / colour-mapped curve).
    procedure AddPoint(const AX, AY, AZ, AValue: Double); overload;
    procedure SetData(const AX, AY, AZ: array of Double); overload;
    procedure SetData(const APoints: array of TPoint3D); overload;
    /// Per-point colour values for a curve or scatter; turns ColorByValue on.
    procedure SetValues(const AValues: array of Double); overload;
    /// Per-vertex colour values C[i][j] for a surface (instead of height).
    procedure SetValues(const C: TRho3DMatrix); overload;
    /// z = f(x, y): X[j] (columns), Y[i] (rows), Z[i][j]. NaN in Z is a hole.
    procedure SetSurface(const X, Y: array of Double; const Z: TRho3DMatrix);
    /// Parametric surface: X[i][j], Y[i][j], Z[i][j] (all the same shape).
    procedure SetParametricSurface(const X, Y, Z: TRho3DMatrix);
    /// 3D bars: a bar centred on (X[j], Y[i]) from 0 to Z[i][j] (down for a
    /// negative height; NaN = no bar). AWidth is each bar's width as a
    /// fraction (0..1] of the spacing of X and of Y.
    procedure SetBars(const X, Y: array of Double; const Z: TRho3DMatrix;
      const AWidth: Single = 0.8);
    /// Data coordinates of point / vertex AIndex (surfaces: i * Cols + j;
    /// bars: the end of bar i * Cols + j).
    function PointAt(AIndex: Integer): TRho3DDataPoint;
    /// Colour value at AIndex (NaN if none).
    function ValueAt(AIndex: Integer): Double;
    /// True when this series is drawn through the colour map.
    function IsColorMapped: Boolean;
    function HasValues: Boolean;
    procedure SaveToJson(const AObj: TJSONObject);
    procedure LoadFromJson(const AObj: TJSONObject);

    property Kind: TRho3DSeriesKind read FKind write SetKind;
    property IsSurface: Boolean read GetIsSurface;
    property IsBars: Boolean read GetIsBars;
    /// skBars: each bar's width as a fraction (0..1] of the grid spacing
    property BarWidth: Single read FBarWidth write SetBarWidth;
    property Points: TList<TPoint3D> read FPoints;
    property Values: TList<Double> read FValues;
    /// number of points (curve / scatter), vertices (surface) or bars
    property Count: Integer read GetCount;
    property Rows: Integer read FRows;
    property Cols: Integer read FCols;
    property Title: string read FTitle write SetTitle;
    property Color: TAlphaColor read FColor write SetColor;
    property Thickness: Single read FThickness write SetThickness;
    property UseGradient: Boolean read FUseGradient write SetUseGradient;
    property GradientStartColor: TAlphaColor read FGradientStartColor write SetGradientStartColor;
    property GradientEndColor: TAlphaColor read FGradientEndColor write SetGradientEndColor;
    property Visible: Boolean read FVisible write SetVisible;
    property ShowInLegend: Boolean read FShowInLegend write SetShowInLegend;
    /// draw the connecting polyline (curves)
    property ShowLine: Boolean read FShowLine write SetShowLine;
    /// draw a marker at each point (always on for scatter)
    property ShowPoints: Boolean read FShowPoints write SetShowPoints;
    /// marker size in pixels
    property PointSize: Single read FPointSize write SetPointSize;
    property MarkerShape: TRho3DMarker read FMarkerShape write SetMarkerShape;
    /// 0 (invisible) .. 1 (opaque)
    property Opacity: Single read FOpacity write SetOpacity;
    property ColorMap: TRho3DColorMap read FColorMap write SetColorMap;
    /// colour through ColorMap (surface: by height or SetValues; scatter /
    /// curve: by SetValues) instead of the solid Color
    property ColorByValue: Boolean read FColorByValue write SetColorByValue;
    property FillMode: TRho3DFillMode read FFillMode write SetFillMode;
    property EdgeColor: TAlphaColor read FEdgeColor write SetEdgeColor;
    property EdgeWidth: Single read FEdgeWidth write SetEdgeWidth;
    /// flat Lambert lighting of surface faces
    property Shaded: Boolean read FShaded write SetShaded;
  end;

  TRho3DPlot = class(TSkCustomControl)
  public const
    DefaultLineColor       = TAlphaColors.Dodgerblue;
    DefaultGradientStart   = TAlphaColors.Deepskyblue;
    DefaultGradientEnd     = TAlphaColors.Orangered;
    // light theme (the default)
    DefaultCubeColor       = TAlphaColor($66000000);
    DefaultAxisColor       = TAlphaColor($FF404040);
    DefaultTextColor       = TAlphaColor($FF202020);
    DefaultBackgroundColor = TAlphaColor($FFFFFFFF);
    DefaultGridColor       = TAlphaColor($24000000);
    DefaultPaneColor       = TAlphaColor($0A000000);
    DefaultEdgeColor       = TAlphaColor($55000000);
    // dark theme
    DarkCubeColor          = TAlphaColor($40FFFFFF);
    DarkAxisColor          = TAlphaColor($FFC0C0C0);
    DarkTextColor          = TAlphaColor($FFDCDCDC);
    DarkBackgroundColor    = TAlphaColor($FF1A1A20);
    DarkGridColor          = TAlphaColor($26FFFFFF);
    DarkPaneColor          = TAlphaColor($0CFFFFFF);
    /// faces above this count are drawn as one triangle batch (no
    /// antialiasing) instead of individual antialiased paths
    BatchFaceThreshold = 6000;
    /// target face / point counts while dragging
    InteractiveFaces  = 6000;
    InteractivePoints = 15000;
    /// max curve chunks in the depth sort when surfaces are present
    MaxCurveItems = 12000;
  private type
    // dkBar: one bar, its six faces from FFaces[Index] on
    TDrawKind = (dkFace, dkCurve, dkMarker, dkBar);
    TDrawItem = record
      Series: Integer;
      Kind: TDrawKind;
      Index: Integer;
      Count: Integer;
    end;
    TInteractMode = (imNone, imRotate, imPan, imLegend);
  strict private
    FSeries: TObjectList<TRho3DSeries>;
    FPrepared: Boolean;
    FFrame: TRho3DFrame;
    FClip: Boolean;
    FUseFixedBounds: Boolean;
    FFixedMin, FFixedMax: TPoint3D;
    FLimits: array[0..5] of Double;           // XMin, XMax, YMin, YMax, ZMin, ZMax
    FAspect: TRho3DAspect;
    FAspectRatio: array[0..2] of Single;
    FColorMin, FColorMax: Double;             // NaN = automatic
    FCLo, FCHi: Double;                       // resolved colour range
    // view
    FCam: TRho3DCamera;
    FTicks: array[0..2] of TArray<Double>;
    FTickStep: array[0..2] of Double;
    // named ticks per axis (SetTickLabels): data positions and labels; none =
    // round-number ticks. FTickText: the labels of FTicks in this render.
    FTickPos: array[0..2] of TArray<Double>;
    FTickNames: array[0..2] of TArray<string>;
    FTickText: array[0..2] of TArray<string>;
    FBoxBack: array[0..2, 0..1] of Boolean;
    FLightVec: TPoint3D;
    // screen state captured on the last on-screen render
    FScreenPass: Boolean;
    FScreenCenter: TPointF;
    FScreenMinWH: Single;
    FSurface: ISkSurface;
    FSurfaceW, FSurfaceH: Integer;
    // mouse
    FPressed: Boolean;
    FMoved: Boolean;
    FMode: TInteractMode;
    FPressPos, FLastPos, FMousePos: TPointF;
    FCtrlDown: Boolean;
    FInteracting: Boolean;
    FHoverSeries, FHoverIndex: Integer;
    FPickTolerance: Single;
    FMenu: TPopupMenu;
    FEditor: TComponent;
    // appearance
    FTheme: TRho3DTheme;
    FShowCube: Boolean;
    FShowAxes: Boolean;
    FShowTicks: Boolean;
    FShowValues: Boolean;
    FShowGrid: Boolean;
    FTickCount: Integer;
    FCubeColor: TAlphaColor;
    FAxisColor: TAlphaColor;
    FTextColor: TAlphaColor;
    FBackgroundColor: TAlphaColor;
    FGridColor: TAlphaColor;
    FPaneColor: TAlphaColor;
    FAxisTitleX, FAxisTitleY, FAxisTitleZ: string;
    FChartTitle: string;
    // font sizes in points: tick numbers (also legend and colour bar), the
    // x, y and z axis titles, chart title
    FTickFontSize, FChartTitleFontSize: Single;
    FAxisTitleFontSize: array[0..2] of Single;
    FShowColorBar: Boolean;
    FColorBarTitle: string;
    FLightAzimuth, FLightElevation, FAmbient: Single;
    // legend
    FLegendVisible: Boolean;
    FLegendLocation: TRho3DLegendLocation;
    FLegendOffset: TPointF;
    FLegendDragOrigin: TPointF;
    FLegendRect: TRectF;
    FLegendRows: TArray<TRectF>;
    FLegendRowSeries: TArray<Integer>;
    // master series style
    FLineColor: TAlphaColor;
    FLineThickness: Single;
    FUseGradient: Boolean;
    FGradientStartColor: TAlphaColor;
    FGradientEndColor: TAlphaColor;
    FShowLines: Boolean;
    FShowPoints: Boolean;
    FPointSize: Single;
    FDepthCue: Boolean;
    FShowHoverInfo: Boolean;
    // animation
    FAutoRotate: Boolean;
    FAutoRotateSpeed: Single;
    FRotateTimer: TTimer;
    FRotateWatch: TStopwatch;
    FRevealFraction: Single;
    FShowRevealHead: Boolean;
    FRevealTimer: TTimer;
    FRevealWatch: TStopwatch;
    FRevealSeconds: Single;
    FOnPointPicked: TRho3DPointPicked;
    FOnViewChanged: TNotifyEvent;
    // per-frame draw list (reused between frames)
    FItems: TArray<TDrawItem>;
    FKeys: TArray<Single>;
    FOrder: TArray<Integer>;
    FItemCount: Integer;
    // triangle batch
    FBatchPos: TArray<TPointF>;
    FBatchCol: TArray<TAlphaColor>;
    FBatchCount: Integer;
    // fonts for the current render
    FFontTick, FFontChart: ISkFont;
    FFontTitle: array[0..2] of ISkFont;   // the axis titles, x, y, z

    procedure RotateTick(Sender: TObject);
    procedure RevealTick(Sender: TObject);
    // prepare
    procedure Prepare;
    procedure ComputeBounds;
    procedure ComputeColorRange;
    procedure PrepareSeries(S: TRho3DSeries);
    procedure BuildFaces(S: TRho3DSeries; const AVal: TArray<Double>;
      AStride: Integer; out AFaces: TArray<TRho3DFace>);
    procedure PrepareBars(S: TRho3DSeries);
    function FacesViewer(S: TRho3DSeries; const F: TRho3DFace): Boolean;
    function MapColor(S: TRho3DSeries; const V: Double): TAlphaColor;
    // transform / draw
    procedure TransformSeries(S: TRho3DSeries);
    function RevealSegments(S: TRho3DSeries): Integer;
    function PointStride(S: TRho3DSeries): Integer;
    function FaceList(S: TRho3DSeries): TArray<TRho3DFace>;
    procedure AddItem(ASeries: Integer; AKind: TDrawKind; AIndex, ACount: Integer;
      const ADepth: Single);
    procedure BuildItems(out AFaceCount: Integer);
    procedure SortItems;
    procedure DrawScene(const ACanvas: ISkCanvas; AVector: Boolean);
    function FaceDrawColor(S: TRho3DSeries; const F: TRho3DFace): TAlphaColor;
    procedure BatchTriangle(const A, B, C: TPointF; AColor: TAlphaColor);
    procedure BatchQuad(const A, B, C, D: TPointF; AColor: TAlphaColor);
    procedure BatchLine(const A, B: TPointF; AWidth: Single; AColor: TAlphaColor);
    procedure FlushBatch(const ACanvas: ISkCanvas);
    procedure DrawCurveChunk(const ACanvas: ISkCanvas; S: TRho3DSeries;
      AStart, ACount: Integer; const APaint: ISkPaint);
    procedure DrawMarker(const ACanvas: ISkCanvas; const P: TPointF;
      ASize: Single; AShape: TRho3DMarker; AColor: TAlphaColor);
    function BoxPoint(A: Integer; const VA: Single; B: Integer; const VB: Single;
      C: Integer; const VC: Single): TPoint3D;
    procedure ComputeBoxFacing;
    procedure DrawBoxBack(const ACanvas: ISkCanvas);
    procedure DrawBoxEdges(const ACanvas: ISkCanvas; AFront: Boolean);
    procedure DrawAxis(const ACanvas: ISkCanvas; A: Integer);
    procedure DrawColorBar(const ACanvas: ISkCanvas; const APlotRect: TRectF;
      S: TRho3DSeries);
    procedure DrawLegend(const ACanvas: ISkCanvas; const APlotRect: TRectF);
    procedure DrawTitle(const ACanvas: ISkCanvas; const ADest: TRectF);
    procedure DrawHover(const ACanvas: ISkCanvas; const ADest: TRectF);
    procedure DrawTextCentered(const ACanvas: ISkCanvas; const AText: string;
      const ACenter: TPointF; const AFont: ISkFont; const APaint: ISkPaint);
    function ColorBarSeries: TRho3DSeries;
    procedure RenderScene(const ACanvas: ISkCanvas; const ADest: TRectF;
      const AClearColor: TAlphaColor; AOverlay: Boolean; AVector: Boolean = False);
    function GetSceneScale: Single;
    procedure SetReducedDetail(const Value: Boolean);
    // interaction helpers
    procedure ZoomAbout(const P: TPointF; AFactor: Single);
    procedure UpdateHover(const X, Y: Single);
    procedure ShowPlotMenu;
    procedure MenuCopyImage(Sender: TObject);
    procedure MenuExportPNG(Sender: TObject);
    procedure MenuExportPDF(Sender: TObject);
    procedure MenuSavePlot(Sender: TObject);
    procedure MenuLoadPlot(Sender: TObject);
    procedure MenuProperties(Sender: TObject);
    procedure MenuResetView(Sender: TObject);
    procedure ViewChanged;
    // property access
    function GetSeries(Index: Integer): TRho3DSeries;
    function GetSeriesCount: Integer;
    function DefaultSeries: TRho3DSeries;
    function GetAzimuth: Single;
    function GetElevation: Single;
    function GetZoom: Single;
    function GetPanX: Single;
    function GetPanY: Single;
    function GetProjection: TRho3DProjection;
    function GetLimit(Index: Integer): Double;
    function GetAspectRatio(Index: Integer): Single;
    procedure SetAzimuth(const Value: Single);
    procedure SetElevation(const Value: Single);
    procedure SetZoom(const Value: Single);
    procedure SetPanX(const Value: Single);
    procedure SetPanY(const Value: Single);
    procedure SetProjection(const Value: TRho3DProjection);
    procedure SetLimit(Index: Integer; const Value: Double);
    procedure SetAspect(const Value: TRho3DAspect);
    procedure SetAspectRatio(Index: Integer; const Value: Single);
    procedure SetColorMin(const Value: Double);
    procedure SetColorMax(const Value: Double);
    procedure SetTheme(const Value: TRho3DTheme);
    procedure SetShowCube(const Value: Boolean);
    procedure SetShowAxes(const Value: Boolean);
    procedure SetShowTicks(const Value: Boolean);
    procedure SetShowValues(const Value: Boolean);
    procedure SetShowGrid(const Value: Boolean);
    procedure SetTickCount(const Value: Integer);
    procedure ComputeTicks(A: Integer);
    procedure SetCubeColor(const Value: TAlphaColor);
    procedure SetAxisColor(const Value: TAlphaColor);
    procedure SetTextColor(const Value: TAlphaColor);
    procedure SetBackgroundColor(const Value: TAlphaColor);
    procedure SetGridColor(const Value: TAlphaColor);
    procedure SetPaneColor(const Value: TAlphaColor);
    procedure SetAxisTitle(Index: Integer; const Value: string);
    function GetAxisTitle(Index: Integer): string;
    procedure SetChartTitle(const Value: string);
    function GetFontSize(Index: Integer): Single;
    procedure SetFontSize(Index: Integer; const Value: Single);
    procedure SetShowColorBar(const Value: Boolean);
    procedure SetColorBarTitle(const Value: string);
    procedure SetLightAzimuth(const Value: Single);
    procedure SetLightElevation(const Value: Single);
    procedure SetAmbient(const Value: Single);
    procedure SetLegendVisible(const Value: Boolean);
    procedure SetLegendLocation(const Value: TRho3DLegendLocation);
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
    procedure SetRevealFraction(const Value: Single);
    procedure SetShowRevealHead(const Value: Boolean);
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
    procedure DoMouseLeave; override;
    procedure DblClick; override;
    procedure KeyDown(var Key: Word; var KeyChar: WideChar;
      Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // ---- data ----
    /// Create a new empty curve series styled from the master properties.
    function AddSeries: TRho3DSeries; overload;
    function AddSeries(const AColor: TAlphaColor): TRho3DSeries; overload;
    /// Add a curve (next palette colour, no gradient).
    function AddCurve(const X, Y, Z: array of Double): TRho3DSeries;
    /// Add a scatter of markers (next palette colour).
    function AddScatter(const X, Y, Z: array of Double): TRho3DSeries;
    /// Add a surface z = f(x, y): X[j], Y[i], Z[i][j], coloured by height.
    function AddSurface(const X, Y: array of Double; const Z: TRho3DMatrix): TRho3DSeries;
    /// Add a parametric surface from X[i][j], Y[i][j], Z[i][j].
    function AddParametricSurface(const X, Y, Z: TRho3DMatrix): TRho3DSeries;
    /// Add 3D bars: a bar centred on (X[j], Y[i]) from 0 to Z[i][j] (down for
    /// a negative height), coloured by height through the colour map, shaded,
    /// with edges. AWidth: each bar's width as a fraction of the grid spacing.
    function AddBars(const X, Y: array of Double; const Z: TRho3DMatrix;
      const AWidth: Single = 0.8): TRho3DSeries;
    procedure DeleteSeries(AIndex: Integer);
    /// Replace all data with a single curve through the given columns.
    procedure SetPlotData(const AX, AY, AZ: array of Double); overload;
    procedure SetPlotData(const APoints: array of TPoint3D); overload;
    /// Append a point to the first series, creating it if needed.
    procedure AddPoint(const AX, AY, AZ: Double);
    /// Remove every series.
    procedure Clear;
    /// Called by a series when its data or appearance changes.
    procedure SeriesChanged;
    /// Freeze the frame to a data range (streaming without rescaling).
    procedure SetDataBounds(const AMin, AMax: TPoint3D);
    /// Resume automatic scaling to fit the data (also clears fixed limits).
    procedure AutoScale;
    /// Named ticks on axis AAxis (0 = x, 1 = y, 2 = z): ALabels[k] at the data
    /// position APositions[k], drawn in place of the round-number ticks (the
    /// grid lines follow them), for example category names under bars.
    /// Positions outside the axis range are not drawn. Empty arrays go back
    /// to round-number ticks.
    procedure SetTickLabels(AAxis: Integer; const APositions: array of Double;
      const ALabels: array of string);
    /// Whether axis AAxis has named ticks.
    function HasTickLabels(AAxis: Integer): Boolean;
    /// Resolved data range of the box on axis 0..2 (after limits).
    function AxisRange(AAxis: Integer; out ALo, AHi: Double): Boolean;
    /// Resolved colour range.
    procedure ColorRange(out ALo, AHi: Double);

    // ---- view ----
    procedure ResetView;
    procedure SetView(AAzimuth, AElevation: Single);
    procedure ViewPreset(APreset: TRho3DViewPreset);
    /// Project a data point to control coordinates using the last screen
    /// render's camera (returns False if nothing has been drawn yet).
    function DataToScreen(const AX, AY, AZ: Double; out P: TPointF): Boolean;
    /// Nearest data point to (X, Y) within PickTolerance pixels.
    function FindNearestPoint(const X, Y: Single; out ASeries: TRho3DSeries;
      out AIndex: Integer): Boolean;

    // ---- animation ----
    /// Draw curves progressively from 0 to 1 over ASeconds.
    procedure AnimateReveal(ASeconds: Single);
    procedure StopReveal;

    // ---- export / persistence ----
    /// Raster PNG. 0 x 0 = the on-screen size at the screen's scale (sharp on
    /// HiDPI); otherwise exactly AWidth x AHeight pixels, laid out like the
    /// screen. ATransparent omits the background.
    procedure SaveToPNG(const AFileName: string; AWidth: Integer = 0;
      AHeight: Integer = 0; ATransparent: Boolean = False);
    /// Vector PDF, page AWidth x AHeight points (0 = on-screen size).
    procedure SaveToPDF(const AFileName: string; AWidth: Integer = 0;
      AHeight: Integer = 0);
    /// Draws the plot, as it is now (view, zoom, edits), onto any Skia canvas
    /// (a PDF page, an SVG canvas, a larger bitmap) in ADest, as vectors, as
    /// SaveToPDF does onto its page.
    procedure RenderTo(const ACanvas: ISkCanvas; const ADest: TRectF);
    procedure CopyToClipboard;
    /// Render to a raster image (same sizing rules as SaveToPNG).
    function MakeImage(AWidth: Integer = 0; AHeight: Integer = 0;
      ATransparent: Boolean = False): ISkImage;
    /// Whole plot state (series data and style, view, axes, legend, theme).
    /// The caller owns the result.
    function SaveToJson: TJSONObject;
    procedure LoadFromJson(const AObj: TJSONObject);
    procedure SavePlotToFile(const AFileName: string);
    procedure LoadPlotFromFile(const AFileName: string);
    /// Open the run-time property editor.
    procedure ShowEditor;

    // ---- view state ----
    property Azimuth: Single read GetAzimuth write SetAzimuth;
    property Elevation: Single read GetElevation write SetElevation;
    property Zoom: Single read GetZoom write SetZoom;
    /// pan as a fraction of Min(width, height) of the plot area
    property PanX: Single read GetPanX write SetPanX;
    property PanY: Single read GetPanY write SetPanY;
    // ---- axis limits (NaN = automatic) ----
    property XMin: Double index 0 read GetLimit write SetLimit;
    property XMax: Double index 1 read GetLimit write SetLimit;
    property YMin: Double index 2 read GetLimit write SetLimit;
    property YMax: Double index 3 read GetLimit write SetLimit;
    property ZMin: Double index 4 read GetLimit write SetLimit;
    property ZMax: Double index 5 read GetLimit write SetLimit;
    /// fixed colour range (NaN = automatic from the data)
    property ColorMin: Double read FColorMin write SetColorMin;
    property ColorMax: Double read FColorMax write SetColorMax;
    property SeriesCount: Integer read GetSeriesCount;
    property Series[Index: Integer]: TRho3DSeries read GetSeries;
    property PickTolerance: Single read FPickTolerance write FPickTolerance;
    /// Draw large data at reduced detail (coarser surfaces, every k-th
    /// point). Switched on automatically while the user drags.
    property ReducedDetail: Boolean read FInteracting write SetReducedDetail;
  published
    property Theme: TRho3DTheme read FTheme write SetTheme default thLight;
    property Projection: TRho3DProjection read GetProjection write SetProjection default ppPerspective;
    property Aspect: TRho3DAspect read FAspect write SetAspect default asIndependent;
    /// relative box lengths for Aspect = asCustom
    property AspectX: Single index 0 read GetAspectRatio write SetAspectRatio;
    property AspectY: Single index 1 read GetAspectRatio write SetAspectRatio;
    property AspectZ: Single index 2 read GetAspectRatio write SetAspectRatio;
    property ChartTitle: string read FChartTitle write SetChartTitle;
    /// font sizes in points: tick numbers (also the legend and colour bar,
    /// 11 by default), each axis title (12.5) and the chart title (15, bold)
    property TickFontSize: Single index 0 read GetFontSize write SetFontSize;
    property AxisTitleFontSizeX: Single index 1 read GetFontSize write SetFontSize;
    property AxisTitleFontSizeY: Single index 2 read GetFontSize write SetFontSize;
    property AxisTitleFontSizeZ: Single index 3 read GetFontSize write SetFontSize;
    property ChartTitleFontSize: Single index 4 read GetFontSize write SetFontSize;
    property ShowCube: Boolean read FShowCube write SetShowCube default True;
    property ShowAxes: Boolean read FShowAxes write SetShowAxes default True;
    property ShowTicks: Boolean read FShowTicks write SetShowTicks default True;
    property ShowValues: Boolean read FShowValues write SetShowValues default True;
    /// grid lines (and a faint fill) on the three back faces of the box
    property ShowGrid: Boolean read FShowGrid write SetShowGrid default True;
    /// approximate number of tick intervals per axis (round-number ticks)
    property TickCount: Integer read FTickCount write SetTickCount default 5;
    property CubeColor: TAlphaColor read FCubeColor write SetCubeColor default DefaultCubeColor;
    property AxisColor: TAlphaColor read FAxisColor write SetAxisColor default DefaultAxisColor;
    property TextColor: TAlphaColor read FTextColor write SetTextColor default DefaultTextColor;
    property BackgroundColor: TAlphaColor read FBackgroundColor write SetBackgroundColor default DefaultBackgroundColor;
    property GridColor: TAlphaColor read FGridColor write SetGridColor default DefaultGridColor;
    property PaneColor: TAlphaColor read FPaneColor write SetPaneColor default DefaultPaneColor;
    property AxisTitleX: string index 0 read GetAxisTitle write SetAxisTitle;
    property AxisTitleY: string index 1 read GetAxisTitle write SetAxisTitle;
    property AxisTitleZ: string index 2 read GetAxisTitle write SetAxisTitle;
    property ShowColorBar: Boolean read FShowColorBar write SetShowColorBar default True;
    property ColorBarTitle: string read FColorBarTitle write SetColorBarTitle;
    /// light direction relative to the viewer, degrees
    property LightAzimuth: Single read FLightAzimuth write SetLightAzimuth;
    property LightElevation: Single read FLightElevation write SetLightElevation;
    /// ambient light level 0..1
    property Ambient: Single read FAmbient write SetAmbient;
    property LegendVisible: Boolean read FLegendVisible write SetLegendVisible default True;
    property LegendLocation: TRho3DLegendLocation read FLegendLocation write SetLegendLocation default llTopRight;
    // master line style (applies to all series)
    property LineColor: TAlphaColor read FLineColor write SetLineColor default DefaultLineColor;
    property LineThickness: Single read FLineThickness write SetLineThickness;
    property UseGradient: Boolean read FUseGradient write SetUseGradient default True;
    property GradientStartColor: TAlphaColor read FGradientStartColor write SetGradientStartColor default DefaultGradientStart;
    property GradientEndColor: TAlphaColor read FGradientEndColor write SetGradientEndColor default DefaultGradientEnd;
    property ShowLines: Boolean read FShowLines write SetShowLines default True;
    property ShowPoints: Boolean read FShowPoints write SetShowPoints default False;
    property PointSize: Single read FPointSize write SetPointSize;
    /// fade markers toward the background with distance
    property DepthCue: Boolean read FDepthCue write SetDepthCue default False;
    property ShowHoverInfo: Boolean read FShowHoverInfo write FShowHoverInfo default True;
    property AutoRotate: Boolean read FAutoRotate write SetAutoRotate default False;
    /// degrees per second
    property AutoRotateSpeed: Single read FAutoRotateSpeed write SetAutoRotateSpeed;
    /// fraction of each curve drawn, 0..1
    property RevealFraction: Single read FRevealFraction write SetRevealFraction;
    /// marker at the head of each curve
    property ShowRevealHead: Boolean read FShowRevealHead write SetShowRevealHead default False;
    property OnPointPicked: TRho3DPointPicked read FOnPointPicked write FOnPointPicked;
    property OnViewChanged: TNotifyEvent read FOnViewChanged write FOnViewChanged;

    property Align;
    property Anchors;
    property Height;
    property Width;
    property Position;
    property Size;
    property Visible;
    property HitTest;
    property TabOrder;
    property TabStop;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
  end;

const
  SeriesKindNames: array[TRho3DSeriesKind] of string =
    ('curve', 'scatter', 'surface', 'parametricSurface', 'bars');
  FillModeNames: array[TRho3DFillMode] of string =
    ('filled', 'wireframe', 'filledWithEdges');
  MarkerNames: array[TRho3DMarker] of string =
    ('circle', 'square', 'diamond', 'triangle', 'cross');
  ProjectionNames: array[TRho3DProjection] of string =
    ('perspective', 'orthographic');
  AspectNames: array[TRho3DAspect] of string = ('independent', 'equal', 'custom');
  ThemeNames: array[TRho3DTheme] of string = ('light', 'dark');
  LegendLocationNames: array[TRho3DLegendLocation] of string =
    ('topRight', 'topLeft', 'bottomRight', 'bottomLeft');
  /// the keys of the axes' named ticks in SaveToJson
  TickLabelKeys: array[0..2] of string = ('tickLabelsX', 'tickLabelsY', 'tickLabelsZ');
  ViewPresetNames: array[TRho3DViewPreset] of string =
    ('isometric', 'top', 'front', 'side');

  /// file format version written by SaveToJson
  Rho3DJsonVersion = 1;

implementation

uses
  System.IOUtils,
  System.Rtti,
  FMX.Graphics,
  FMX.Forms,
  FMX.Dialogs,
  FMX.Platform,
  Rho3DJsonUtils,
  Rho3DPlotEditor;

const
  PaletteColors: array[0..9] of TAlphaColor = (
    $FF1F77B4, $FFFF7F0E, $FF2CA02C, $FFD62728, $FF9467BD,
    $FF8C564B, $FFE377C2, $FF7F7F7F, $FFBCBD22, $FF17BECF);

function NameIndex(const ANames: array of string; const S: string;
  ADefault: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to High(ANames) do
    if SameText(ANames[i], S) then
      Exit(i);
  Result := ADefault;
end;

function StrOr(const A, B: string): string; inline;
begin
  if A <> '' then Result := A else Result := B;
end;

function IsFinitePt(const P: TPointF): Boolean; inline;
begin
  Result := not IsNan(P.X);
end;

function NaNPoint3D: TPoint3D;
begin
  Result := TPoint3D.Create(NaN, NaN, NaN);
end;

function MatrixShapeOK(const M: TRho3DMatrix; ARows, ACols: Integer): Boolean;
var
  i: Integer;
begin
  Result := Length(M) >= ARows;
  if Result then
    for i := 0 to ARows - 1 do
      if Length(M[i]) < ACols then
        Exit(False);
end;

function CopyMatrix(const M: TRho3DMatrix): TRho3DMatrix;
var
  i: Integer;
begin
  SetLength(Result, Length(M));
  for i := 0 to High(M) do
    Result[i] := Copy(M[i]);
end;

// The distance between neighbouring bar centres: the smallest gap between
// distinct values of C, or 1 when there is none (a single row or column).
function BarSpacing(const C: TArray<Double>): Double;
var
  s: TArray<Double>;
  k: Integer;
  d: Double;
begin
  Result := 0;
  s := Copy(C);
  TArray.Sort<Double>(s);
  for k := 1 to High(s) do
  begin
    d := s[k] - s[k - 1];
    if (d > 0) and not IsInfinite(d) and ((Result = 0) or (d < Result)) then
      Result := d;
  end;
  if Result = 0 then
    Result := 1;
end;

function FiniteValue(const V: Double): Boolean; inline;
begin
  Result := not (IsNan(V) or IsInfinite(V));
end;

{ ==================================================================== }
{ TRho3DSeries                                                          }
{ ==================================================================== }

constructor TRho3DSeries.Create(AOwner: TRho3DPlot);
begin
  inherited Create;
  FOwner := AOwner;
  FPoints := TList<TPoint3D>.Create;
  FValues := TList<Double>.Create;
  FKind := skCurve;
  FVisible := True;
  FShowInLegend := True;
  FThickness := 1.5;
  FColor := TRho3DPlot.DefaultLineColor;
  FUseGradient := True;
  FGradientStartColor := TRho3DPlot.DefaultGradientStart;
  FGradientEndColor := TRho3DPlot.DefaultGradientEnd;
  FShowLine := True;
  FShowPoints := False;
  FPointSize := 6;
  FOpacity := 1;
  FColorMap := cmViridis;
  FMarkerShape := mkCircle;
  FFillMode := fmFilledWithEdges;
  FEdgeColor := TRho3DPlot.DefaultEdgeColor;
  FEdgeWidth := 0.5;
  FBarWidth := 0.8;
end;

destructor TRho3DSeries.Destroy;
begin
  FPoints.Free;
  FValues.Free;
  inherited;
end;

procedure TRho3DSeries.Changed;
begin
  if FOwner <> nil then
    FOwner.SeriesChanged;
end;

function TRho3DSeries.GetCount: Integer;
begin
  if IsSurface or IsBars then
    Result := FRows * FCols
  else
    Result := FPoints.Count;
end;

function TRho3DSeries.GetIsSurface: Boolean;
begin
  Result := FKind in [skSurface, skParametricSurface];
end;

function TRho3DSeries.GetIsBars: Boolean;
begin
  Result := FKind = skBars;
end;

function TRho3DSeries.HasValues: Boolean;
begin
  if IsSurface or IsBars then
    Result := FRows > 0
  else
    Result := FValues.Count > 0;
end;

function TRho3DSeries.IsColorMapped: Boolean;
begin
  Result := FColorByValue and HasValues;
end;

function TRho3DSeries.ColorValueAt(AIndex: Integer): Double;
var
  i, j: Integer;
begin
  Result := NaN;
  if IsSurface or IsBars then
  begin
    if (FCols = 0) or (AIndex < 0) or (AIndex >= FRows * FCols) then Exit;
    i := AIndex div FCols;
    j := AIndex mod FCols;
    if FSurfC <> nil then
      Result := FSurfC[i][j]
    else
      Result := FSurfZ[i][j];
  end
  else if (AIndex >= 0) and (AIndex < FValues.Count) then
    Result := FValues[AIndex];
end;

function TRho3DSeries.ValueAt(AIndex: Integer): Double;
begin
  Result := ColorValueAt(AIndex);
end;

function TRho3DSeries.PointAt(AIndex: Integer): TRho3DDataPoint;
var
  i, j: Integer;
  p: TPoint3D;
begin
  if IsSurface or IsBars then
  begin
    i := AIndex div FCols;
    j := AIndex mod FCols;
    Result.X := FSurfX[i][j];
    Result.Y := FSurfY[i][j];
    Result.Z := FSurfZ[i][j];
  end
  else
  begin
    p := FPoints[AIndex];
    Result.X := p.X;
    Result.Y := p.Y;
    Result.Z := p.Z;
  end;
end;

procedure TRho3DSeries.Clear;
begin
  FPoints.Clear;
  FValues.Clear;
  FRows := 0;
  FCols := 0;
  FGridX := nil; FGridY := nil;
  FSurfX := nil; FSurfY := nil; FSurfZ := nil; FSurfC := nil;
  Changed;
end;

procedure TRho3DSeries.AddPoint(const AX, AY, AZ: Double);
begin
  FPoints.Add(TPoint3D.Create(AX, AY, AZ));
  if FValues.Count > 0 then
    FValues.Add(NaN);
  Changed;
end;

procedure TRho3DSeries.AddPoint(const AX, AY, AZ, AValue: Double);
begin
  // keep values aligned with points
  while FValues.Count < FPoints.Count do
    FValues.Add(NaN);
  FPoints.Add(TPoint3D.Create(AX, AY, AZ));
  FValues.Add(AValue);
  Changed;
end;

procedure TRho3DSeries.SetData(const AX, AY, AZ: array of Double);
var
  i, n: Integer;
begin
  FPoints.Clear;
  FValues.Clear;
  n := Min(Length(AX), Min(Length(AY), Length(AZ)));
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
  FValues.Clear;
  FPoints.Capacity := Length(APoints);
  for i := 0 to High(APoints) do
    FPoints.Add(APoints[i]);
  Changed;
end;

procedure TRho3DSeries.SetValues(const AValues: array of Double);
var
  i: Integer;
begin
  FValues.Clear;
  FValues.Capacity := Length(AValues);
  for i := 0 to High(AValues) do
    FValues.Add(AValues[i]);
  FColorByValue := FValues.Count > 0;
  Changed;
end;

procedure TRho3DSeries.SetValues(const C: TRho3DMatrix);
begin
  if C = nil then
    FSurfC := nil
  else
  begin
    if not MatrixShapeOK(C, FRows, FCols) then
      raise EArgumentException.Create('SetValues: C must have the surface''s Rows x Cols shape');
    FSurfC := CopyMatrix(C);
  end;
  FColorByValue := True;
  Changed;
end;

procedure TRho3DSeries.SetSurface(const X, Y: array of Double; const Z: TRho3DMatrix);
begin
  if (Length(Y) < 2) or (Length(X) < 2) then
    raise EArgumentException.Create('SetSurface: need at least 2 x 2 grid points');
  if not MatrixShapeOK(Z, Length(Y), Length(X)) then
    raise EArgumentException.Create('SetSurface: Z must be Length(Y) rows x Length(X) columns');
  FKind := skSurface;
  SetGrid(X, Y, Z);
end;

procedure TRho3DSeries.SetBars(const X, Y: array of Double; const Z: TRho3DMatrix;
  const AWidth: Single);
begin
  if (Length(Y) < 1) or (Length(X) < 1) then
    raise EArgumentException.Create('SetBars: need at least one bar');
  if not MatrixShapeOK(Z, Length(Y), Length(X)) then
    raise EArgumentException.Create('SetBars: Z must be Length(Y) rows x Length(X) columns');
  FKind := skBars;
  FBarWidth := EnsureRange(AWidth, 0.01, 1);
  SetGrid(X, Y, Z);
end;

// The grid of a surface or of bars: X[j] (columns), Y[i] (rows), Z[i][j].
procedure TRho3DSeries.SetGrid(const X, Y: array of Double; const Z: TRho3DMatrix);
var
  i, j, nr, nc: Integer;
begin
  nc := Length(X);
  nr := Length(Y);
  FRows := nr;
  FCols := nc;
  SetLength(FGridX, nc);
  for j := 0 to nc - 1 do FGridX[j] := X[j];
  SetLength(FGridY, nr);
  for i := 0 to nr - 1 do FGridY[i] := Y[i];
  SetLength(FSurfX, nr);
  SetLength(FSurfY, nr);
  SetLength(FSurfZ, nr);
  for i := 0 to nr - 1 do
  begin
    SetLength(FSurfX[i], nc);
    SetLength(FSurfY[i], nc);
    SetLength(FSurfZ[i], nc);
    for j := 0 to nc - 1 do
    begin
      FSurfX[i][j] := X[j];
      FSurfY[i][j] := Y[i];
      FSurfZ[i][j] := Z[i][j];
    end;
  end;
  FSurfC := nil;
  FPoints.Clear;
  FValues.Clear;
  Changed;
end;

procedure TRho3DSeries.SetParametricSurface(const X, Y, Z: TRho3DMatrix);
var
  nr, nc: Integer;
begin
  nr := Length(X);
  if nr > 0 then nc := Length(X[0]) else nc := 0;
  if (nr < 2) or (nc < 2) then
    raise EArgumentException.Create('SetParametricSurface: need at least 2 x 2 grid points');
  if not (MatrixShapeOK(X, nr, nc) and MatrixShapeOK(Y, nr, nc) and MatrixShapeOK(Z, nr, nc)) then
    raise EArgumentException.Create('SetParametricSurface: X, Y and Z must have the same shape');
  FKind := skParametricSurface;
  FRows := nr;
  FCols := nc;
  FGridX := nil;
  FGridY := nil;
  FSurfX := CopyMatrix(X);
  FSurfY := CopyMatrix(Y);
  FSurfZ := CopyMatrix(Z);
  FSurfC := nil;
  FPoints.Clear;
  FValues.Clear;
  Changed;
end;

procedure TRho3DSeries.SetKind(const Value: TRho3DSeriesKind);
begin
  if FKind = Value then Exit;
  // surfaces are created by SetSurface / SetParametricSurface; only the
  // point kinds can be switched freely
  if (Value in [skCurve, skScatter]) and (FKind in [skCurve, skScatter]) then
  begin
    FKind := Value;
    if Value = skScatter then
      FShowPoints := True;
    Changed;
  end;
end;

procedure TRho3DSeries.SetTitle(const Value: string);
begin
  if FTitle <> Value then begin FTitle := Value; Changed; end;
end;

procedure TRho3DSeries.SetBarWidth(const Value: Single);
var
  v: Single;
begin
  v := EnsureRange(Value, 0.01, 1);
  if FBarWidth <> v then begin FBarWidth := v; Changed; end;
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

procedure TRho3DSeries.SetShowInLegend(const Value: Boolean);
begin
  if FShowInLegend <> Value then begin FShowInLegend := Value; Changed; end;
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

procedure TRho3DSeries.SetOpacity(const Value: Single);
var
  v: Single;
begin
  v := EnsureRange(Value, 0, 1);
  if FOpacity <> v then begin FOpacity := v; Changed; end;
end;

procedure TRho3DSeries.SetColorMap(const Value: TRho3DColorMap);
begin
  if FColorMap <> Value then begin FColorMap := Value; Changed; end;
end;

procedure TRho3DSeries.SetColorByValue(const Value: Boolean);
begin
  if FColorByValue <> Value then begin FColorByValue := Value; Changed; end;
end;

procedure TRho3DSeries.SetMarkerShape(const Value: TRho3DMarker);
begin
  if FMarkerShape <> Value then begin FMarkerShape := Value; Changed; end;
end;

procedure TRho3DSeries.SetFillMode(const Value: TRho3DFillMode);
begin
  if FFillMode <> Value then begin FFillMode := Value; Changed; end;
end;

procedure TRho3DSeries.SetEdgeColor(const Value: TAlphaColor);
begin
  if FEdgeColor <> Value then begin FEdgeColor := Value; Changed; end;
end;

procedure TRho3DSeries.SetEdgeWidth(const Value: Single);
begin
  if FEdgeWidth <> Value then begin FEdgeWidth := Value; Changed; end;
end;

procedure TRho3DSeries.SetShaded(const Value: Boolean);
begin
  if FShaded <> Value then begin FShaded := Value; Changed; end;
end;

procedure TRho3DSeries.SaveToJson(const AObj: TJSONObject);
var
  xs, ys, zs: TArray<Double>;
  i: Integer;
  p: TPoint3D;
begin
  JPutStr(AObj, 'kind', SeriesKindNames[FKind]);
  JPutStr(AObj, 'title', FTitle);
  JPutBool(AObj, 'visible', FVisible);
  JPutBool(AObj, 'showInLegend', FShowInLegend);
  JPutColor(AObj, 'color', FColor);
  JPutFloat(AObj, 'thickness', FThickness);
  JPutBool(AObj, 'useGradient', FUseGradient);
  JPutColor(AObj, 'gradientStart', FGradientStartColor);
  JPutColor(AObj, 'gradientEnd', FGradientEndColor);
  JPutBool(AObj, 'showLine', FShowLine);
  JPutBool(AObj, 'showPoints', FShowPoints);
  JPutFloat(AObj, 'pointSize', FPointSize);
  JPutStr(AObj, 'marker', MarkerNames[FMarkerShape]);
  JPutFloat(AObj, 'opacity', FOpacity);
  JPutStr(AObj, 'colorMap', ColorMapNames[FColorMap]);
  JPutBool(AObj, 'colorByValue', FColorByValue);
  JPutStr(AObj, 'fillMode', FillModeNames[FFillMode]);
  JPutColor(AObj, 'edgeColor', FEdgeColor);
  JPutFloat(AObj, 'edgeWidth', FEdgeWidth);
  JPutBool(AObj, 'shaded', FShaded);
  case FKind of
    skCurve, skScatter:
      begin
        SetLength(xs, FPoints.Count);
        SetLength(ys, FPoints.Count);
        SetLength(zs, FPoints.Count);
        for i := 0 to FPoints.Count - 1 do
        begin
          p := FPoints[i];
          xs[i] := p.X; ys[i] := p.Y; zs[i] := p.Z;
        end;
        JPutVector(AObj, 'x', xs);
        JPutVector(AObj, 'y', ys);
        JPutVector(AObj, 'z', zs);
        if FValues.Count > 0 then
          JPutVector(AObj, 'values', FValues.ToArray);
      end;
    skSurface, skBars:
      begin
        JPutVector(AObj, 'x', FGridX);
        JPutVector(AObj, 'y', FGridY);
        JPutMatrix(AObj, 'z', FSurfZ);
        if FSurfC <> nil then
          JPutMatrix(AObj, 'c', FSurfC);
        if FKind = skBars then
          JPutFloat(AObj, 'barWidth', FBarWidth);
      end;
    skParametricSurface:
      begin
        JPutMatrix(AObj, 'x', FSurfX);
        JPutMatrix(AObj, 'y', FSurfY);
        JPutMatrix(AObj, 'z', FSurfZ);
        if FSurfC <> nil then
          JPutMatrix(AObj, 'c', FSurfC);
      end;
  end;
end;

procedure TRho3DSeries.LoadFromJson(const AObj: TJSONObject);
var
  k: TRho3DSeriesKind;
  xs, ys, zs, vs: TArray<Double>;
  c: TRho3DMatrix;
  colorByValue: Boolean;
begin
  k := TRho3DSeriesKind(NameIndex(SeriesKindNames, JStr(AObj, 'kind', ''), Ord(FKind)));
  FTitle := JStr(AObj, 'title', FTitle);
  FVisible := JBool(AObj, 'visible', FVisible);
  FShowInLegend := JBool(AObj, 'showInLegend', FShowInLegend);
  FColor := JColor(AObj, 'color', FColor);
  FThickness := JFloat(AObj, 'thickness', FThickness);
  FUseGradient := JBool(AObj, 'useGradient', FUseGradient);
  FGradientStartColor := JColor(AObj, 'gradientStart', FGradientStartColor);
  FGradientEndColor := JColor(AObj, 'gradientEnd', FGradientEndColor);
  FShowLine := JBool(AObj, 'showLine', FShowLine);
  FShowPoints := JBool(AObj, 'showPoints', FShowPoints);
  FPointSize := JFloat(AObj, 'pointSize', FPointSize);
  FMarkerShape := TRho3DMarker(NameIndex(MarkerNames, JStr(AObj, 'marker', ''), Ord(FMarkerShape)));
  FOpacity := EnsureRange(JFloat(AObj, 'opacity', FOpacity), 0, 1);
  FColorMap := ColorMapFromName(JStr(AObj, 'colorMap', ''), FColorMap);
  colorByValue := JBool(AObj, 'colorByValue', FColorByValue);
  FFillMode := TRho3DFillMode(NameIndex(FillModeNames, JStr(AObj, 'fillMode', ''), Ord(FFillMode)));
  FEdgeColor := JColor(AObj, 'edgeColor', FEdgeColor);
  FEdgeWidth := JFloat(AObj, 'edgeWidth', FEdgeWidth);
  FShaded := JBool(AObj, 'shaded', FShaded);
  case k of
    skCurve, skScatter:
      begin
        FKind := k;
        xs := JVector(AObj, 'x');
        ys := JVector(AObj, 'y');
        zs := JVector(AObj, 'z');
        SetData(xs, ys, zs);
        vs := JVector(AObj, 'values');
        if vs <> nil then
          SetValues(vs);
      end;
    skSurface:
      begin
        xs := JVector(AObj, 'x');
        ys := JVector(AObj, 'y');
        SetSurface(xs, ys, JMatrix(AObj, 'z'));
        c := JMatrix(AObj, 'c');
        if c <> nil then
          SetValues(c);
      end;
    skBars:
      begin
        xs := JVector(AObj, 'x');
        ys := JVector(AObj, 'y');
        SetBars(xs, ys, JMatrix(AObj, 'z'), JFloat(AObj, 'barWidth', FBarWidth));
        c := JMatrix(AObj, 'c');
        if c <> nil then
          SetValues(c);
      end;
    skParametricSurface:
      begin
        SetParametricSurface(JMatrix(AObj, 'x'), JMatrix(AObj, 'y'), JMatrix(AObj, 'z'));
        c := JMatrix(AObj, 'c');
        if c <> nil then
          SetValues(c);
      end;
  end;
  // SetValues switches colour-by-value on; the saved flag wins
  FColorByValue := colorByValue;
  Changed;
end;

{ ==================================================================== }
{ TRho3DPlot                                                            }
{ ==================================================================== }

constructor TRho3DPlot.Create(AOwner: TComponent);
var
  i: Integer;
begin
  inherited Create(AOwner);
  FSeries := TObjectList<TRho3DSeries>.Create(True);
  HitTest := True;
  AutoCapture := True;
  CanFocus := True;
  TabStop := True;
  FCam.Init;
  for i := 0 to 5 do
    FLimits[i] := NaN;
  FAspect := asIndependent;
  FAspectRatio[0] := 1; FAspectRatio[1] := 1; FAspectRatio[2] := 1;
  FColorMin := NaN;
  FColorMax := NaN;
  FShowCube := True;
  FShowAxes := True;
  FShowTicks := True;
  FShowValues := True;
  FShowGrid := True;
  FTickCount := 5;
  FTickFontSize := 11;
  FAxisTitleFontSize[0] := 12.5;
  FAxisTitleFontSize[1] := 12.5;
  FAxisTitleFontSize[2] := 12.5;
  FChartTitleFontSize := 15;
  FTheme := thLight;
  FCubeColor := DefaultCubeColor;
  FAxisColor := DefaultAxisColor;
  FTextColor := DefaultTextColor;
  FBackgroundColor := DefaultBackgroundColor;
  FGridColor := DefaultGridColor;
  FPaneColor := DefaultPaneColor;
  FAxisTitleX := 'X';
  FAxisTitleY := 'Y';
  FAxisTitleZ := 'Z';
  FShowColorBar := True;
  FLightAzimuth := -45;
  FLightElevation := 45;
  FAmbient := 0.35;
  FLegendVisible := True;
  FLegendLocation := llTopRight;
  FLineColor := DefaultLineColor;
  FLineThickness := 1.5;
  FUseGradient := True;
  FGradientStartColor := DefaultGradientStart;
  FGradientEndColor := DefaultGradientEnd;
  FShowLines := True;
  FShowPoints := False;
  FPointSize := 6;
  FDepthCue := False;
  FShowHoverInfo := True;
  FPickTolerance := 8;
  FAutoRotateSpeed := 30;
  FRevealFraction := 1;
  FHoverSeries := -1;
  FHoverIndex := -1;

  FRotateTimer := TTimer.Create(Self);
  FRotateTimer.Enabled := False;
  FRotateTimer.Interval := 16;
  FRotateTimer.OnTimer := RotateTick;

  FRevealTimer := TTimer.Create(Self);
  FRevealTimer.Enabled := False;
  FRevealTimer.Interval := 16;
  FRevealTimer.OnTimer := RevealTick;
end;

destructor TRho3DPlot.Destroy;
begin
  if FRotateTimer <> nil then
    FRotateTimer.Enabled := False;
  if FRevealTimer <> nil then
    FRevealTimer.Enabled := False;
  FreeAndNil(FEditor);
  FSeries.Free;
  inherited;
end;

{ ---- timers ---- }

procedure TRho3DPlot.RotateTick(Sender: TObject);
var
  dt: Double;
begin
  dt := FRotateWatch.Elapsed.TotalSeconds;
  FRotateWatch := TStopwatch.StartNew;
  if FPressed and FMoved then   // don't fight the user while dragging
    Exit;
  dt := Min(dt, 0.1);
  FCam.Azimuth := FCam.Azimuth + FAutoRotateSpeed * dt;
  if FCam.Azimuth > 180 then
    FCam.Azimuth := FCam.Azimuth - 360
  else if FCam.Azimuth < -180 then
    FCam.Azimuth := FCam.Azimuth + 360;
  Redraw;
end;

procedure TRho3DPlot.RevealTick(Sender: TObject);
var
  f: Single;
begin
  if FRevealSeconds <= 0 then
    f := 1
  else
    f := FRevealWatch.Elapsed.TotalSeconds / FRevealSeconds;
  if f >= 1 then
  begin
    f := 1;
    FRevealTimer.Enabled := False;
  end;
  FRevealFraction := f;
  Redraw;
end;

procedure TRho3DPlot.AnimateReveal(ASeconds: Single);
begin
  FRevealSeconds := ASeconds;
  FRevealFraction := 0;
  FRevealWatch := TStopwatch.StartNew;
  FRevealTimer.Enabled := True;
  Redraw;
end;

procedure TRho3DPlot.StopReveal;
begin
  FRevealTimer.Enabled := False;
end;

{ ---- view ---- }

procedure TRho3DPlot.ViewChanged;
begin
  Redraw;
  if Assigned(FOnViewChanged) then
    FOnViewChanged(Self);
end;

procedure TRho3DPlot.ResetView;
var
  proj: TRho3DProjection;
begin
  proj := FCam.Projection;
  FCam.Init;
  FCam.Projection := proj;
  ViewChanged;
end;

procedure TRho3DPlot.SetView(AAzimuth, AElevation: Single);
begin
  FCam.Azimuth := AAzimuth;
  FCam.Elevation := EnsureRange(AElevation, -90, 90);
  ViewChanged;
end;

procedure TRho3DPlot.ViewPreset(APreset: TRho3DViewPreset);
begin
  case APreset of
    vpIsometric: SetView(-60, 30);
    vpTop:       SetView(0, 90);
    vpFront:     SetView(0, 0);
    vpSide:      SetView(90, 0);
  end;
end;

function TRho3DPlot.GetAzimuth: Single;
begin
  Result := FCam.Azimuth;
end;

function TRho3DPlot.GetElevation: Single;
begin
  Result := FCam.Elevation;
end;

function TRho3DPlot.GetZoom: Single;
begin
  Result := FCam.Zoom;
end;

function TRho3DPlot.GetPanX: Single;
begin
  Result := FCam.PanX;
end;

function TRho3DPlot.GetPanY: Single;
begin
  Result := FCam.PanY;
end;

function TRho3DPlot.GetProjection: TRho3DProjection;
begin
  Result := FCam.Projection;
end;

procedure TRho3DPlot.SetAzimuth(const Value: Single);
begin
  FCam.Azimuth := Value;
  ViewChanged;
end;

procedure TRho3DPlot.SetElevation(const Value: Single);
begin
  FCam.Elevation := EnsureRange(Value, -90, 90);
  ViewChanged;
end;

procedure TRho3DPlot.SetZoom(const Value: Single);
begin
  FCam.Zoom := EnsureRange(Value, 0.05, 100);
  ViewChanged;
end;

procedure TRho3DPlot.SetPanX(const Value: Single);
begin
  FCam.PanX := Value;
  ViewChanged;
end;

procedure TRho3DPlot.SetPanY(const Value: Single);
begin
  FCam.PanY := Value;
  ViewChanged;
end;

procedure TRho3DPlot.SetProjection(const Value: TRho3DProjection);
begin
  if FCam.Projection <> Value then
  begin
    FCam.Projection := Value;
    ViewChanged;
  end;
end;

{ ---- series management ---- }

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

function TRho3DPlot.AddCurve(const X, Y, Z: array of Double): TRho3DSeries;
begin
  Result := AddSeries(PaletteColors[FSeries.Count mod Length(PaletteColors)]);
  Result.FShowLine := True;
  Result.SetData(X, Y, Z);
end;

function TRho3DPlot.AddScatter(const X, Y, Z: array of Double): TRho3DSeries;
begin
  Result := AddSeries(PaletteColors[FSeries.Count mod Length(PaletteColors)]);
  Result.FKind := skScatter;
  Result.FShowLine := False;
  Result.FShowPoints := True;
  Result.SetData(X, Y, Z);
end;

function TRho3DPlot.AddSurface(const X, Y: array of Double;
  const Z: TRho3DMatrix): TRho3DSeries;
begin
  Result := AddSeries;
  Result.FUseGradient := False;
  Result.FColor := PaletteColors[(FSeries.Count - 1) mod Length(PaletteColors)];
  Result.FColorByValue := True;
  try
    Result.SetSurface(X, Y, Z);
  except
    FSeries.Remove(Result);
    raise;
  end;
end;

function TRho3DPlot.AddParametricSurface(const X, Y, Z: TRho3DMatrix): TRho3DSeries;
begin
  Result := AddSeries;
  Result.FUseGradient := False;
  Result.FColor := PaletteColors[(FSeries.Count - 1) mod Length(PaletteColors)];
  Result.FColorByValue := True;
  try
    Result.SetParametricSurface(X, Y, Z);
  except
    FSeries.Remove(Result);
    raise;
  end;
end;

function TRho3DPlot.AddBars(const X, Y: array of Double; const Z: TRho3DMatrix;
  const AWidth: Single): TRho3DSeries;
begin
  Result := AddSeries;
  Result.FUseGradient := False;
  Result.FColor := PaletteColors[(FSeries.Count - 1) mod Length(PaletteColors)];
  Result.FColorByValue := True;
  Result.FShaded := True;   // so the top and the sides of a bar differ
  try
    Result.SetBars(X, Y, Z, AWidth);
  except
    FSeries.Remove(Result);
    raise;
  end;
end;

procedure TRho3DPlot.DeleteSeries(AIndex: Integer);
begin
  FSeries.Delete(AIndex);
  FHoverSeries := -1;
  SeriesChanged;
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
  FHoverSeries := -1;
  AddSeries.SetData(AX, AY, AZ);
end;

procedure TRho3DPlot.SetPlotData(const APoints: array of TPoint3D);
begin
  FSeries.Clear;
  FHoverSeries := -1;
  AddSeries.SetData(APoints);
end;

procedure TRho3DPlot.AddPoint(const AX, AY, AZ: Double);
begin
  DefaultSeries.AddPoint(AX, AY, AZ);
end;

procedure TRho3DPlot.Clear;
begin
  FSeries.Clear;
  FHoverSeries := -1;
  SeriesChanged;
end;

procedure TRho3DPlot.SeriesChanged;
begin
  FPrepared := False;
  Redraw;
end;

procedure TRho3DPlot.SetDataBounds(const AMin, AMax: TPoint3D);
begin
  FFixedMin := AMin;
  FFixedMax := AMax;
  FUseFixedBounds := True;
  SeriesChanged;
end;

procedure TRho3DPlot.AutoScale;
var
  i: Integer;
begin
  FUseFixedBounds := False;
  for i := 0 to 5 do
    FLimits[i] := NaN;
  SeriesChanged;
end;

function TRho3DPlot.AxisRange(AAxis: Integer; out ALo, AHi: Double): Boolean;
begin
  Prepare;
  Result := (AAxis >= 0) and (AAxis <= 2);
  if Result then
  begin
    ALo := FFrame.Lo[AAxis];
    AHi := FFrame.Hi[AAxis];
  end;
end;

procedure TRho3DPlot.ColorRange(out ALo, AHi: Double);
begin
  Prepare;
  ALo := FCLo;
  AHi := FCHi;
end;

{ ==================================================================== }
{ Prepare: bounds, normalisation, colours, faces                        }
{ ==================================================================== }

procedure TRho3DPlot.Prepare;
var
  s: TRho3DSeries;
begin
  if FPrepared then
    Exit;
  ComputeBounds;
  ComputeColorRange;
  for s in FSeries do
    PrepareSeries(s);
  FPrepared := True;
end;

procedure TRho3DPlot.ComputeBounds;
var
  lo, hi: array[0..2] of Double;
  have: array[0..2] of Boolean;

  procedure Acc(const X, Y, Z: Double);
  var
    v: array[0..2] of Double;
    a: Integer;
  begin
    if IsNan(X) or IsNan(Y) or IsNan(Z) then Exit;
    v[0] := X; v[1] := Y; v[2] := Z;
    for a := 0 to 2 do
      if not have[a] then
      begin
        lo[a] := v[a]; hi[a] := v[a]; have[a] := True;
      end
      else
      begin
        if v[a] < lo[a] then lo[a] := v[a];
        if v[a] > hi[a] then hi[a] := v[a];
      end;
  end;

var
  s: TRho3DSeries;
  i, j, a: Integer;
  p: TPoint3D;
  hx, hy, z: Double;
begin
  for a := 0 to 2 do
  begin
    have[a] := False;
    lo[a] := -1;
    hi[a] := 1;
  end;
  if FUseFixedBounds then
  begin
    lo[0] := FFixedMin.X; hi[0] := FFixedMax.X;
    lo[1] := FFixedMin.Y; hi[1] := FFixedMax.Y;
    lo[2] := FFixedMin.Z; hi[2] := FFixedMax.Z;
  end
  else
  begin
    // every series counts, visible or not, so hiding one never rescales
    for s in FSeries do
      if s.IsBars then
      begin
        // each bar's whole box, from 0 to its height
        hx := s.FBarWidth * BarSpacing(s.FGridX) / 2;
        hy := s.FBarWidth * BarSpacing(s.FGridY) / 2;
        for i := 0 to s.FRows - 1 do
          for j := 0 to s.FCols - 1 do
          begin
            z := s.FSurfZ[i][j];
            if FiniteValue(z) then
            begin
              Acc(s.FGridX[j] - hx, s.FGridY[i] - hy, Min(0, z));
              Acc(s.FGridX[j] + hx, s.FGridY[i] + hy, Max(0, z));
            end;
          end;
      end
      else if s.IsSurface then
      begin
        for i := 0 to s.FRows - 1 do
          for j := 0 to s.FCols - 1 do
            Acc(s.FSurfX[i][j], s.FSurfY[i][j], s.FSurfZ[i][j]);
      end
      else
        for i := 0 to s.FPoints.Count - 1 do
        begin
          p := s.FPoints[i];
          Acc(p.X, p.Y, p.Z);
        end;
  end;
  FClip := FUseFixedBounds;
  for a := 0 to 2 do
  begin
    if not IsNan(FLimits[a * 2]) then
    begin
      lo[a] := FLimits[a * 2];
      FClip := True;
    end;
    if not IsNan(FLimits[a * 2 + 1]) then
    begin
      hi[a] := FLimits[a * 2 + 1];
      FClip := True;
    end;
  end;
  FFrame.Setup(lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], FAspect,
    FAspectRatio[0], FAspectRatio[1], FAspectRatio[2]);
end;

procedure TRho3DPlot.ComputeColorRange;
var
  s: TRho3DSeries;
  i, n: Integer;
  v, lo, hi: Double;
  have: Boolean;
begin
  have := False;
  lo := 0; hi := 1;
  for s in FSeries do
  begin
    if not s.IsColorMapped then
      Continue;
    n := s.Count;
    for i := 0 to n - 1 do
    begin
      v := s.ColorValueAt(i);
      if IsNan(v) or IsInfinite(v) then
        Continue;
      if not have then
      begin
        lo := v; hi := v; have := True;
      end
      else
      begin
        if v < lo then lo := v;
        if v > hi then hi := v;
      end;
    end;
  end;
  if not IsNan(FColorMin) then lo := FColorMin;
  if not IsNan(FColorMax) then hi := FColorMax;
  if hi <= lo then
  begin
    v := Max(Abs(lo) * 0.1, 0.5);
    lo := lo - v;
    hi := hi + v;
  end;
  FCLo := lo;
  FCHi := hi;
end;

function TRho3DPlot.MapColor(S: TRho3DSeries; const V: Double): TAlphaColor;
begin
  if IsNan(V) then
    Result := S.FColor
  else
    Result := ColorMapColor(S.FColorMap, (V - FCLo) / (FCHi - FCLo));
end;

procedure TRho3DPlot.PrepareSeries(S: TRho3DSeries);
var
  i, j, n, k: Integer;
  p: TPoint3D;
  vals: TArray<Double>;
  mapped: Boolean;
  stride, faces: Integer;
begin
  mapped := S.IsColorMapped;
  if S.IsBars then
    PrepareBars(S)
  else if S.IsSurface then
  begin
    n := S.FRows * S.FCols;
    SetLength(S.FNorm, n);
    SetLength(vals, n);
    for i := 0 to S.FRows - 1 do
      for j := 0 to S.FCols - 1 do
      begin
        k := i * S.FCols + j;
        if IsNan(S.FSurfX[i][j]) or IsNan(S.FSurfY[i][j]) or IsNan(S.FSurfZ[i][j]) then
          S.FNorm[k] := NaNPoint3D
        else
        begin
          p := FFrame.Normalize(S.FSurfX[i][j], S.FSurfY[i][j], S.FSurfZ[i][j]);
          if FClip and not FFrame.Inside(p) then
            p := NaNPoint3D;
          S.FNorm[k] := p;
        end;
        if mapped then
          vals[k] := S.ColorValueAt(k)
        else
          vals[k] := NaN;
      end;
    S.FPtColor := nil;
    BuildFaces(S, vals, 1, S.FFaces);
    faces := (S.FRows - 1) * (S.FCols - 1);
    if faces > InteractiveFaces then
    begin
      stride := Ceil(Sqrt(faces / InteractiveFaces));
      BuildFaces(S, vals, stride, S.FCoarseFaces);
    end
    else
      S.FCoarseFaces := S.FFaces;
  end
  else
  begin
    n := S.FPoints.Count;
    SetLength(S.FNorm, n);
    SetLength(S.FPtColor, n);
    for i := 0 to n - 1 do
    begin
      p := S.FPoints[i];
      if IsNan(p.X) or IsNan(p.Y) or IsNan(p.Z) then
        S.FNorm[i] := NaNPoint3D
      else
      begin
        p := FFrame.Normalize(p.X, p.Y, p.Z);
        if FClip and not FFrame.Inside(p) then
          p := NaNPoint3D;
        S.FNorm[i] := p;
      end;
      if mapped then
        S.FPtColor[i] := MapColor(S, S.ColorValueAt(i))
      else if S.FUseGradient and (n > 1) then
        // quantised to 256 steps so long runs share a colour (fast drawing)
        S.FPtColor[i] := LerpColor(S.FGradientStartColor, S.FGradientEndColor,
          Round(i / (n - 1) * 255) / 255)
      else
        S.FPtColor[i] := S.FColor;
      if S.FOpacity < 1 then
        S.FPtColor[i] := FadeColor(S.FPtColor[i], S.FOpacity);
    end;
    S.FFaces := nil;
    S.FCoarseFaces := nil;
  end;
end;

procedure TRho3DPlot.BuildFaces(S: TRho3DSeries; const AVal: TArray<Double>;
  AStride: Integer; out AFaces: TArray<TRho3DFace>);
var
  i0, i1, j0, j1, n, cnt, m: Integer;
  f: TRho3DFace;
  p0, p1, p2, p3, d1, d2, nrm: TPoint3D;
  sum: Double;
  len: Single;

  procedure AddVal(K: Integer);
  begin
    if not IsNan(AVal[K]) then
    begin
      sum := sum + AVal[K];
      Inc(m);
    end;
  end;

begin
  cnt := 0;
  n := ((S.FRows - 2) div AStride + 1) * ((S.FCols - 2) div AStride + 1);
  SetLength(AFaces, n);
  i0 := 0;
  while i0 < S.FRows - 1 do
  begin
    i1 := Min(i0 + AStride, S.FRows - 1);
    j0 := 0;
    while j0 < S.FCols - 1 do
    begin
      j1 := Min(j0 + AStride, S.FCols - 1);
      f.I0 := i0 * S.FCols + j0;
      f.I1 := i0 * S.FCols + j1;
      f.I2 := i1 * S.FCols + j1;
      f.I3 := i1 * S.FCols + j0;
      p0 := S.FNorm[f.I0]; p1 := S.FNorm[f.I1];
      p2 := S.FNorm[f.I2]; p3 := S.FNorm[f.I3];
      if not (IsNan(p0.X) or IsNan(p1.X) or IsNan(p2.X) or IsNan(p3.X)) then
      begin
        d1 := p2 - p0;
        d2 := p3 - p1;
        nrm := d1.CrossProduct(d2);
        len := nrm.Length;
        if len > 1E-12 then
          f.Normal := nrm / len
        else
          f.Normal := TPoint3D.Create(0, 0, 1);
        if S.IsColorMapped then
        begin
          sum := 0; m := 0;
          AddVal(f.I0); AddVal(f.I1); AddVal(f.I2); AddVal(f.I3);
          if m > 0 then
            f.Color := MapColor(S, sum / m)
          else
            f.Color := S.FColor;
        end
        else
          f.Color := S.FColor;
        if cnt >= Length(AFaces) then
          SetLength(AFaces, cnt * 2 + 16);
        AFaces[cnt] := f;
        Inc(cnt);
      end;
      j0 := j1;
    end;
    i0 := i1;
  end;
  SetLength(AFaces, cnt);
end;

{ Bars. For n = Rows * Cols bars the vertex arrays hold first one point per
  bar, the centre of its end (its top, or its bottom when it goes down), so
  hover and picking find bar i * Cols + j at that index as on a surface; then
  the eight corners of each bar: corner k of bar b at n + 8 b + k, bit 0 of k
  choosing the high x, bit 1 the high y, bit 2 the high z. FFaces holds the
  six faces of each bar shown, six in a row, with outward normals; a bar with
  a NaN height, or outside clipped limits, has none. }
procedure TRho3DPlot.PrepareBars(S: TRho3DSeries);
const
  // the faces -x, +x, -y, +y, -z, +z: their corners, in order round the face
  FaceCorners: array[0..5, 0..3] of Integer = ((0, 2, 6, 4), (1, 3, 7, 5),
    (0, 1, 5, 4), (2, 3, 7, 6), (0, 1, 3, 2), (4, 5, 7, 6));
  FaceNormals: array[0..5, 0..2] of Single = ((-1, 0, 0), (1, 0, 0),
    (0, -1, 0), (0, 1, 0), (0, 0, -1), (0, 0, 1));
var
  i, j, b, k, n, base, cnt: Integer;
  hx, hy, z: Double;
  lo, hi, p: TPoint3D;
  col: TAlphaColor;
  f: TRho3DFace;
  ok: Boolean;

  // Clips the bar's box to the plot box; False when none of it is inside.
  function ClipBox(var L, H: TPoint3D): Boolean;
  var
    a: Integer;
    m: Single;
  begin
    for a := 0 to 2 do
    begin
      m := FFrame.Half[a];
      if (H.V[a] < -m) or (L.V[a] > m) then
        Exit(False);
      L.V[a] := Max(L.V[a], -m);
      H.V[a] := Min(H.V[a], m);
    end;
    Result := True;
  end;

begin
  n := S.FRows * S.FCols;
  SetLength(S.FNorm, 9 * n);
  SetLength(S.FFaces, 6 * n);
  S.FPtColor := nil;
  cnt := 0;
  hx := S.FBarWidth * BarSpacing(S.FGridX) / 2;
  hy := S.FBarWidth * BarSpacing(S.FGridY) / 2;
  for i := 0 to S.FRows - 1 do
    for j := 0 to S.FCols - 1 do
    begin
      b := i * S.FCols + j;
      base := n + 8 * b;
      z := S.FSurfZ[i][j];
      ok := FiniteValue(z) and FiniteValue(S.FGridX[j]) and FiniteValue(S.FGridY[i]);
      if ok then
      begin
        lo := FFrame.Normalize(S.FGridX[j] - hx, S.FGridY[i] - hy, Min(0, z));
        hi := FFrame.Normalize(S.FGridX[j] + hx, S.FGridY[i] + hy, Max(0, z));
        if FClip then
          ok := ClipBox(lo, hi);
      end;
      if not ok then
      begin
        S.FNorm[b] := NaNPoint3D;
        for k := 0 to 7 do
          S.FNorm[base + k] := NaNPoint3D;
        Continue;
      end;
      for k := 0 to 7 do
      begin
        if k and 1 <> 0 then p.X := hi.X else p.X := lo.X;
        if k and 2 <> 0 then p.Y := hi.Y else p.Y := lo.Y;
        if k and 4 <> 0 then p.Z := hi.Z else p.Z := lo.Z;
        S.FNorm[base + k] := p;
      end;
      p.X := (lo.X + hi.X) / 2;
      p.Y := (lo.Y + hi.Y) / 2;
      if z >= 0 then p.Z := hi.Z else p.Z := lo.Z;
      S.FNorm[b] := p;
      if S.IsColorMapped then
        col := MapColor(S, S.ColorValueAt(b))
      else
        col := S.FColor;
      for k := 0 to 5 do
      begin
        f.I0 := base + FaceCorners[k, 0];
        f.I1 := base + FaceCorners[k, 1];
        f.I2 := base + FaceCorners[k, 2];
        f.I3 := base + FaceCorners[k, 3];
        f.Color := col;
        f.Normal := TPoint3D.Create(FaceNormals[k, 0], FaceNormals[k, 1], FaceNormals[k, 2]);
        S.FFaces[cnt] := f;
        Inc(cnt);
      end;
    end;
  SetLength(S.FFaces, cnt);
  S.FCoarseFaces := S.FFaces;
end;

// Whether a bar's face is turned towards the viewer (its outward normal
// points at the eye; for perspective, from the face's centre).
function TRho3DPlot.FacesViewer(S: TRho3DSeries; const F: TRho3DFace): Boolean;
var
  nv, c: TPoint3D;
begin
  nv := FCam.RotateVec(F.Normal);
  if FCam.Projection = ppPerspective then
  begin
    // I0 and I2 are opposite corners, so their middle is the face's centre
    c := FCam.ToView((S.FNorm[F.I0] + S.FNorm[F.I2]) * 0.5);
    Result := -nv.X * c.X - nv.Y * c.Y + nv.Z * (FCam.Distance - c.Z) > 0;
  end
  else
    Result := nv.Z > 0;
end;

{ ==================================================================== }
{ Per-frame transform and draw list                                     }
{ ==================================================================== }

procedure TRho3DPlot.TransformSeries(S: TRho3DSeries);
var
  i, n, k: Integer;
  v: TPoint3D;
  dmin, dmax, t, f: Single;
  pn: TPoint3D;
begin
  n := Length(S.FNorm);
  if Length(S.FScr) <> n then
  begin
    SetLength(S.FScr, n);
    SetLength(S.FDepth, n);
  end;
  dmin := MaxSingle;
  dmax := -MaxSingle;
  for i := 0 to n - 1 do
  begin
    if IsNan(S.FNorm[i].X) then
    begin
      S.FScr[i] := TPointF.Create(NaN, NaN);
      S.FDepth[i] := 0;
      Continue;
    end;
    v := FCam.ToView(S.FNorm[i]);
    S.FScr[i] := FCam.ViewToScreen(v);
    S.FDepth[i] := v.Z;
    if v.Z < dmin then dmin := v.Z;
    if v.Z > dmax then dmax := v.Z;
  end;
  S.FDepthMin := dmin;
  S.FDepthMax := dmax;

  // head of a revealed curve (interpolated in box space so perspective is right)
  S.FHeadValid := False;
  if (S.FKind in [skCurve, skScatter]) and (n > 0) then
  begin
    t := FRevealFraction * (n - 1);
    k := Min(Floor(t), n - 1);
    f := t - k;
    if (k < n - 1) and (f > 0) and not IsNan(S.FNorm[k].X) and not IsNan(S.FNorm[k + 1].X) then
    begin
      pn := S.FNorm[k] + (S.FNorm[k + 1] - S.FNorm[k]) * f;
      v := FCam.ToView(pn);
      S.FHeadScr := FCam.ViewToScreen(v);
      S.FHeadDepth := v.Z;
      S.FHeadColor := S.FPtColor[k];
      S.FHeadValid := True;
    end
    else if not IsNan(S.FNorm[k].X) then
    begin
      S.FHeadScr := S.FScr[k];
      S.FHeadDepth := S.FDepth[k];
      S.FHeadColor := S.FPtColor[k];
      S.FHeadValid := True;
    end;
  end;
end;

function TRho3DPlot.RevealSegments(S: TRho3DSeries): Integer;
var
  n: Integer;
begin
  n := Length(S.FNorm);
  if n < 2 then
    Exit(0);
  if FRevealFraction >= 1 then
    Result := n - 1
  else
    Result := EnsureRange(Floor(FRevealFraction * (n - 1)), 0, n - 1);
end;

function TRho3DPlot.PointStride(S: TRho3DSeries): Integer;
begin
  // curves and scatters also thin out while auto-rotating, so a very long
  // trajectory spins smoothly; surfaces keep full detail there
  if (FInteracting or FRotateTimer.Enabled) and (Length(S.FNorm) > InteractivePoints) then
    Result := Ceil(Length(S.FNorm) / InteractivePoints)
  else
    Result := 1;
end;

function TRho3DPlot.FaceList(S: TRho3DSeries): TArray<TRho3DFace>;
begin
  if FInteracting then
    Result := S.FCoarseFaces
  else
    Result := S.FFaces;
end;

procedure TRho3DPlot.AddItem(ASeries: Integer; AKind: TDrawKind;
  AIndex, ACount: Integer; const ADepth: Single);
begin
  if FItemCount >= Length(FItems) then
  begin
    SetLength(FItems, FItemCount * 2 + 256);
    SetLength(FKeys, Length(FItems));
  end;
  FItems[FItemCount].Series := ASeries;
  FItems[FItemCount].Kind := AKind;
  FItems[FItemCount].Index := AIndex;
  FItems[FItemCount].Count := ACount;
  FKeys[FItemCount] := ADepth;
  Inc(FItemCount);
end;

procedure TRho3DPlot.BuildItems(out AFaceCount: Integer);
var
  si, fi, i, n, m, st, chunk, cnt, last, curves: Integer;
  s: TRho3DSeries;
  faces: TArray<TRho3DFace>;
  d: Single;
  hasFaces: Boolean;

  function ChunkDepth(A, B: Integer): Single;
  var
    k, c, idx: Integer;
    sum: Single;
  begin
    sum := 0; c := 0;
    for k := 0 to 2 do
    begin
      idx := A + (B - A) * k div 2;
      if not IsNan(s.FNorm[idx].X) then
      begin
        sum := sum + s.FDepth[idx];
        Inc(c);
      end;
    end;
    if c > 0 then Result := sum / c else Result := 0;
  end;

var
  // the view direction: view depth (larger = nearer) of a box point is
  // toward.X x + toward.Y y + toward.Z z; the eye sits at Distance * toward
  toward: TPoint3D;
  horiz, zBase: Single;

  // The sort key of a bar. Bars stand on one plane and never overlap there,
  // so whole bars drawn far to near, by where they stand, hide each other
  // correctly; ordering their faces one by one does not (a tall bar's side
  // can be nearer than a short neighbour's top). Orthographic: the depth of
  // the bar's foot on the base plane. Perspective: nearer the eye across the
  // ground is nearer, scaled to roughly match the depths of other items.
  function BarKey(const P: TPoint3D): Single;
  begin
    if FCam.Projection = ppPerspective then
      Result := (FCam.Distance * horiz - Hypot(P.X - FCam.Distance * toward.X,
        P.Y - FCam.Distance * toward.Y)) * Max(horiz, 0.05) + toward.Z * zBase
    else
      Result := toward.X * P.X + toward.Y * P.Y + toward.Z * zBase;
  end;

begin
  FItemCount := 0;
  AFaceCount := 0;
  hasFaces := False;
  curves := 0;
  toward := TPoint3D.Create(FCam.ToView(TPoint3D.Create(1, 0, 0)).Z,
    FCam.ToView(TPoint3D.Create(0, 1, 0)).Z, FCam.ToView(TPoint3D.Create(0, 0, 1)).Z);
  horiz := Hypot(toward.X, toward.Y);
  zBase := EnsureRange(FFrame.NormAxis(2, 0), -FFrame.Half[2], FFrame.Half[2]);
  for s in FSeries do
    if s.FVisible then
    begin
      if (s.IsSurface or s.IsBars) and (Length(s.FFaces) > 0) then
        hasFaces := True
      else if (s.FKind = skCurve) and s.FShowLine then
        Inc(curves);
    end;

  for si := 0 to FSeries.Count - 1 do
  begin
    s := FSeries[si];
    if not s.FVisible then
      Continue;
    if s.IsBars then
    begin
      // one item per bar; its first face's first corner, I0 = n + 8 b, gives
      // the bar's number b and so its point at the end (centred over its foot)
      n := s.FRows * s.FCols;
      fi := 0;
      while fi < Length(s.FFaces) do
      begin
        AddItem(si, dkBar, fi, 6, BarKey(s.FNorm[(s.FFaces[fi].I0 - n) div 8]));
        Inc(fi, 6);
      end;
      Inc(AFaceCount, Length(s.FFaces) div 2);   // three faces of a bar show
      Continue;
    end;
    if s.IsSurface then
    begin
      faces := FaceList(s);
      for fi := 0 to High(faces) do
      begin
        d := (s.FDepth[faces[fi].I0] + s.FDepth[faces[fi].I1] +
          s.FDepth[faces[fi].I2] + s.FDepth[faces[fi].I3]) * 0.25;
        AddItem(si, dkFace, fi, 0, d);
      end;
      Inc(AFaceCount, Length(faces));
      Continue;
    end;

    n := Length(s.FNorm);
    st := PointStride(s);
    m := RevealSegments(s);
    // polyline, split into chunks so it can interleave with faces
    if (s.FKind = skCurve) and s.FShowLine and (n >= 2) then
    begin
      if hasFaces then
      begin
        chunk := Max(1, Ceil(m / Max(1, MaxCurveItems div Max(curves, 1))));
        chunk := ((chunk + st - 1) div st) * st;
      end
      else
        chunk := Max(m, 1);
      i := 0;
      repeat
        cnt := Min(chunk, m - i);
        AddItem(si, dkCurve, i, cnt, ChunkDepth(i, Min(i + Max(cnt, 1), n - 1)));
        Inc(i, chunk);
      until i >= m;
    end;
    // markers
    if (s.FKind = skScatter) or s.FShowPoints then
    begin
      if s.FKind = skScatter then
        last := n - 1
      else
        last := Min(m, n - 1);
      if FRevealFraction >= 1 then
        last := n - 1;
      i := 0;
      while i <= last do
      begin
        if not IsNan(s.FNorm[i].X) then
          AddItem(si, dkMarker, i, 0, s.FDepth[i]);
        Inc(i, st);
      end;
    end;
    if FShowRevealHead and s.FHeadValid and (s.FKind = skCurve) then
      AddItem(si, dkMarker, -1, 0, s.FHeadDepth + 1E-4);
  end;
end;

procedure SortOrder(const Keys: TArray<Single>; var Order: TArray<Integer>;
  L, R: Integer);
var
  i, j, t: Integer;
  p: Single;
begin
  while R - L > 16 do
  begin
    i := L;
    j := R;
    p := Keys[Order[(L + R) shr 1]];
    repeat
      while Keys[Order[i]] < p do Inc(i);
      while Keys[Order[j]] > p do Dec(j);
      if i <= j then
      begin
        t := Order[i]; Order[i] := Order[j]; Order[j] := t;
        Inc(i); Dec(j);
      end;
    until i > j;
    if j - L < R - i then
    begin
      SortOrder(Keys, Order, L, j);
      L := i;
    end
    else
    begin
      SortOrder(Keys, Order, i, R);
      R := j;
    end;
  end;
  for i := L + 1 to R do
  begin
    t := Order[i];
    p := Keys[t];
    j := i - 1;
    while (j >= L) and (Keys[Order[j]] > p) do
    begin
      Order[j + 1] := Order[j];
      Dec(j);
    end;
    Order[j + 1] := t;
  end;
end;

procedure TRho3DPlot.SortItems;
var
  i: Integer;
begin
  if Length(FOrder) < FItemCount then
    SetLength(FOrder, Length(FItems));
  for i := 0 to FItemCount - 1 do
    FOrder[i] := i;
  if FItemCount > 1 then
    SortOrder(FKeys, FOrder, 0, FItemCount - 1);
end;

function TRho3DPlot.FaceDrawColor(S: TRho3DSeries; const F: TRho3DFace): TAlphaColor;
var
  nv: TPoint3D;
  dot: Single;
begin
  Result := F.Color;
  if S.FShaded then
  begin
    nv := FCam.RotateVec(F.Normal);
    dot := Abs(nv.X * FLightVec.X + nv.Y * FLightVec.Y + nv.Z * FLightVec.Z);
    Result := ShadeColor(Result, FAmbient + (1 - FAmbient) * dot);
  end;
  if S.FOpacity < 1 then
    Result := FadeColor(Result, S.FOpacity);
end;

procedure TRho3DPlot.BatchTriangle(const A, B, C: TPointF; AColor: TAlphaColor);
begin
  if FBatchCount + 3 > Length(FBatchPos) then
  begin
    SetLength(FBatchPos, Length(FBatchPos) * 2 + 3 * 1024);
    SetLength(FBatchCol, Length(FBatchPos));
  end;
  FBatchPos[FBatchCount] := A;
  FBatchPos[FBatchCount + 1] := B;
  FBatchPos[FBatchCount + 2] := C;
  FBatchCol[FBatchCount] := AColor;
  FBatchCol[FBatchCount + 1] := AColor;
  FBatchCol[FBatchCount + 2] := AColor;
  Inc(FBatchCount, 3);
end;

procedure TRho3DPlot.BatchQuad(const A, B, C, D: TPointF; AColor: TAlphaColor);
begin
  BatchTriangle(A, B, C, AColor);
  BatchTriangle(A, C, D, AColor);
end;

procedure TRho3DPlot.BatchLine(const A, B: TPointF; AWidth: Single; AColor: TAlphaColor);
var
  dx, dy, len: Single;
  nx, ny: Single;
begin
  dx := B.X - A.X;
  dy := B.Y - A.Y;
  len := Sqrt(dx * dx + dy * dy);
  if len < 1E-6 then
    Exit;
  nx := -dy / len * AWidth * 0.5;
  ny := dx / len * AWidth * 0.5;
  BatchQuad(TPointF.Create(A.X + nx, A.Y + ny), TPointF.Create(B.X + nx, B.Y + ny),
    TPointF.Create(B.X - nx, B.Y - ny), TPointF.Create(A.X - nx, A.Y - ny), AColor);
end;

procedure TRho3DPlot.FlushBatch(const ACanvas: ISkCanvas);
var
  verts: ISkVertices;
  paint: ISkPaint;
begin
  if FBatchCount = 0 then
    Exit;
  verts := TSkVertices.MakeCopy(TSkVertexMode.Triangles,
    Copy(FBatchPos, 0, FBatchCount), nil, Copy(FBatchCol, 0, FBatchCount));
  paint := TSkPaint.Create;
  paint.AntiAlias := False;
  paint.Color := TAlphaColors.White;
  ACanvas.DrawVertices(verts, TSkBlendMode.Modulate, paint);
  FBatchCount := 0;
end;

procedure TRho3DPlot.DrawCurveChunk(const ACanvas: ISkCanvas; S: TRho3DSeries;
  AStart, ACount: Integer; const APaint: ISkPaint);
var
  pb: ISkPathBuilder;
  runLen: Integer;
  runColor: TAlphaColor;
  lastPt: TPointF;
  st, a, b, last, n, mLim: Integer;
  partial: Boolean;

  // one stroked path per run of equal colour: far faster than a stroke per
  // segment, and overlaps inside a translucent run do not darken
  procedure Flush;
  begin
    if runLen >= 2 then
    begin
      APaint.Color := runColor;
      ACanvas.DrawPath(pb.Detach, APaint);
    end
    else if runLen > 0 then
      pb.Detach;   // discard
    runLen := 0;
  end;

  procedure Segment(const P, Q: TPointF; C: TAlphaColor);
  begin
    if (runLen > 0) and (C = runColor) and (lastPt = P) then
    begin
      pb.LineTo(Q);
      Inc(runLen);
    end
    else
    begin
      Flush;
      runColor := C;
      pb.MoveTo(P);
      pb.LineTo(Q);
      runLen := 2;
    end;
    lastPt := Q;
  end;

begin
  n := Length(S.FScr);
  st := PointStride(S);
  mLim := RevealSegments(S);
  last := Min(AStart + ACount, n - 1);
  pb := TSkPathBuilder.Create;
  runLen := 0;
  runColor := 0;
  a := AStart;
  while a < last do
  begin
    b := Min(a + st, last);
    if IsFinitePt(S.FScr[a]) and IsFinitePt(S.FScr[b]) then
      Segment(S.FScr[a], S.FScr[b], S.FPtColor[a])
    else
      Flush;
    a := b;
  end;
  // the partial segment to the head of a revealed curve
  partial := (FRevealFraction < 1) and S.FHeadValid and (last = mLim) and
    (mLim < n - 1) and IsFinitePt(S.FScr[mLim]);
  if partial then
    Segment(S.FScr[mLim], S.FHeadScr, S.FPtColor[mLim]);
  Flush;
end;

procedure TRho3DPlot.DrawMarker(const ACanvas: ISkCanvas; const P: TPointF;
  ASize: Single; AShape: TRho3DMarker; AColor: TAlphaColor);
var
  paint: ISkPaint;
  r: Single;
  pb: ISkPathBuilder;
begin
  r := ASize / 2;
  if r <= 0 then
    Exit;
  paint := TSkPaint.Create(TSkPaintStyle.Fill);
  paint.AntiAlias := True;
  paint.Color := AColor;
  case AShape of
    mkCircle:
      ACanvas.DrawCircle(P, r, paint);
    mkSquare:
      ACanvas.DrawRect(TRectF.Create(P.X - r, P.Y - r, P.X + r, P.Y + r), paint);
    mkDiamond, mkTriangle:
      begin
        pb := TSkPathBuilder.Create;
        if AShape = mkDiamond then
        begin
          r := r * 1.2;
          pb.MoveTo(P.X, P.Y - r);
          pb.LineTo(P.X + r, P.Y);
          pb.LineTo(P.X, P.Y + r);
          pb.LineTo(P.X - r, P.Y);
        end
        else
        begin
          r := r * 1.2;
          pb.MoveTo(P.X, P.Y - r);
          pb.LineTo(P.X + r * 0.866, P.Y + r * 0.5);
          pb.LineTo(P.X - r * 0.866, P.Y + r * 0.5);
        end;
        pb.Close;
        ACanvas.DrawPath(pb.Detach, paint);
      end;
    mkCross:
      begin
        paint.Style := TSkPaintStyle.Stroke;
        paint.StrokeWidth := Max(1.5, ASize / 5);
        ACanvas.DrawLine(PointF(P.X - r, P.Y - r), PointF(P.X + r, P.Y + r), paint);
        ACanvas.DrawLine(PointF(P.X - r, P.Y + r), PointF(P.X + r, P.Y - r), paint);
      end;
  end;
end;

procedure TRho3DPlot.DrawScene(const ACanvas: ISkCanvas; AVector: Boolean);
var
  k, faceCount: Integer;
  it: TDrawItem;
  s: TRho3DSeries;
  useBatch: Boolean;
  c: TAlphaColor;
  fillPaint, seamPaint, edgePaint, linePaint: ISkPaint;
  pb: ISkPathBuilder;
  faces: TArray<TRho3DFace>;
  lastFaceSeries: Integer;
  fade: Single;

  // One quad of a surface or a bar: filled, with edges, or as a wireframe.
  procedure DrawFace(S: TRho3DSeries; const F: TRho3DFace);
  var
    c, ec: TAlphaColor;
    ew: Single;
    p0, p1, p2, p3: TPointF;
    path: ISkPath;
  begin
    p0 := S.FScr[F.I0]; p1 := S.FScr[F.I1];
    p2 := S.FScr[F.I2]; p3 := S.FScr[F.I3];
    c := FaceDrawColor(S, F);
    if S.FFillMode = fmWireframe then
    begin
      if S.IsColorMapped then
        ec := c
      else
        ec := FadeColor(S.FEdgeColor, S.FOpacity);
      ew := Max(S.FEdgeWidth, 1);
    end
    else
    begin
      ec := FadeColor(S.FEdgeColor, S.FOpacity);
      ew := S.FEdgeWidth;
    end;
    if useBatch then
    begin
      if S.FFillMode <> fmWireframe then
        BatchQuad(p0, p1, p2, p3, c);
      if S.FFillMode <> fmFilled then
      begin
        ew := Max(ew, 0.8);
        BatchLine(p0, p1, ew, ec);
        BatchLine(p1, p2, ew, ec);
        BatchLine(p2, p3, ew, ec);
        BatchLine(p3, p0, ew, ec);
      end;
    end
    else
    begin
      pb.MoveTo(p0);
      pb.LineTo(p1);
      pb.LineTo(p2);
      pb.LineTo(p3);
      pb.Close;
      path := pb.Detach;
      if S.FFillMode <> fmWireframe then
      begin
        fillPaint.Color := c;
        ACanvas.DrawPath(path, fillPaint);
        if S.FFillMode = fmFilled then
        begin
          // stroke in the face colour to hide antialiasing seams
          seamPaint.Color := c;
          ACanvas.DrawPath(path, seamPaint);
        end;
      end;
      if (S.FFillMode <> fmFilled) and (ew > 0) then
      begin
        edgePaint.Color := ec;
        edgePaint.StrokeWidth := ew;
        ACanvas.DrawPath(path, edgePaint);
      end;
    end;
  end;

  // A bar: the faces turned towards the viewer (they never overlap each
  // other); a translucent bar shows its far faces through them, first.
  procedure DrawBar(S: TRho3DSeries; AFirst: Integer);
  var
    m: Integer;
  begin
    if S.FOpacity < 1 then
      for m := AFirst to AFirst + 5 do
        if not FacesViewer(S, S.FFaces[m]) then
          DrawFace(S, S.FFaces[m]);
    for m := AFirst to AFirst + 5 do
      if FacesViewer(S, S.FFaces[m]) then
        DrawFace(S, S.FFaces[m]);
  end;

begin
  BuildItems(faceCount);
  if FItemCount = 0 then
    Exit;
  SortItems;
  // big surfaces go through one triangle batch (fast, not antialiased);
  // vector output (PDF) always draws real paths
  useBatch := (not AVector) and (faceCount > BatchFaceThreshold);

  fillPaint := TSkPaint.Create(TSkPaintStyle.Fill);
  fillPaint.AntiAlias := True;
  seamPaint := TSkPaint.Create(TSkPaintStyle.Stroke);
  seamPaint.AntiAlias := True;
  seamPaint.StrokeWidth := 0.6;
  seamPaint.StrokeJoin := TSkStrokeJoin.Round;
  edgePaint := TSkPaint.Create(TSkPaintStyle.Stroke);
  edgePaint.AntiAlias := True;
  edgePaint.StrokeJoin := TSkStrokeJoin.Round;
  linePaint := TSkPaint.Create(TSkPaintStyle.Stroke);
  linePaint.AntiAlias := True;
  pb := TSkPathBuilder.Create;
  FBatchCount := 0;
  lastFaceSeries := -1;

  for k := 0 to FItemCount - 1 do
  begin
    it := FItems[FOrder[k]];
    s := FSeries[it.Series];
    case it.Kind of
      dkFace:
        begin
          if it.Series <> lastFaceSeries then
          begin
            faces := FaceList(s);
            lastFaceSeries := it.Series;
          end;
          DrawFace(s, faces[it.Index]);
        end;
      dkBar:
        DrawBar(s, it.Index);
      dkCurve:
        begin
          FlushBatch(ACanvas);
          linePaint.StrokeWidth := s.FThickness;
          if s.FThickness > 1.5 then
          begin
            linePaint.StrokeCap := TSkStrokeCap.Round;
            linePaint.StrokeJoin := TSkStrokeJoin.Round;
          end
          else
          begin
            linePaint.StrokeCap := TSkStrokeCap.Butt;
            linePaint.StrokeJoin := TSkStrokeJoin.Bevel;
          end;
          DrawCurveChunk(ACanvas, s, it.Index, it.Count, linePaint);
        end;
      dkMarker:
        begin
          FlushBatch(ACanvas);
          if it.Index < 0 then
          begin
            // head of a revealed curve: a ringed dot
            DrawMarker(ACanvas, s.FHeadScr, Max(s.FPointSize, s.FThickness * 3) + 4,
              mkCircle, FBackgroundColor);
            DrawMarker(ACanvas, s.FHeadScr, Max(s.FPointSize, s.FThickness * 3),
              mkCircle, s.FHeadColor or $FF000000);
          end
          else
          begin
            c := s.FPtColor[it.Index];
            if FDepthCue and (s.FDepthMax > s.FDepthMin) then
            begin
              fade := (s.FDepthMax - s.FDepth[it.Index]) / (s.FDepthMax - s.FDepthMin);
              c := LerpColor(c, FBackgroundColor and $00FFFFFF or (c and $FF000000), fade * 0.75);
            end;
            DrawMarker(ACanvas, s.FScr[it.Index], s.FPointSize, s.FMarkerShape, c);
          end;
        end;
    end;
  end;
  FlushBatch(ACanvas);
end;

{ ==================================================================== }
{ Box, grid and axes                                                    }
{ ==================================================================== }

function TRho3DPlot.BoxPoint(A: Integer; const VA: Single; B: Integer;
  const VB: Single; C: Integer; const VC: Single): TPoint3D;
var
  q: array[0..2] of Single;
begin
  q[A] := VA;
  q[B] := VB;
  q[C] := VC;
  Result := TPoint3D.Create(q[0], q[1], q[2]);
end;

procedure TRho3DPlot.ComputeBoxFacing;
var
  a, si, b, c: Integer;
  side: Single;
  nrm, ctr, nv, cv: TPoint3D;
begin
  for a := 0 to 2 do
  begin
    b := (a + 1) mod 3;
    c := (a + 2) mod 3;
    for si := 0 to 1 do
    begin
      side := 2 * si - 1;
      nrm := BoxPoint(a, side, b, 0, c, 0);
      ctr := BoxPoint(a, side * FFrame.Half[a], b, 0, c, 0);
      nv := FCam.RotateVec(nrm);
      cv := FCam.ToView(ctr);
      if FCam.Projection = ppOrthographic then
        FBoxBack[a, si] := nv.Z < 0
      else
        FBoxBack[a, si] := (nv.X * -cv.X + nv.Y * -cv.Y + nv.Z * (FCam.Distance - cv.Z)) < 0;
    end;
  end;
end;

procedure TRho3DPlot.DrawBoxBack(const ACanvas: ISkCanvas);
var
  a, si, b, c, k, ax, q: Integer;
  side, hb, hc, ha, t: Single;
  inPlane: array[0..1] of Integer;
  pb: ISkPathBuilder;
  panePaint, gridPaint: ISkPaint;
begin
  if not FShowGrid then
    Exit;
  panePaint := TSkPaint.Create(TSkPaintStyle.Fill);
  panePaint.AntiAlias := True;
  panePaint.Color := FPaneColor;
  gridPaint := TSkPaint.Create(TSkPaintStyle.Stroke);
  gridPaint.AntiAlias := True;
  gridPaint.StrokeWidth := 1;
  gridPaint.Color := FGridColor;
  for a := 0 to 2 do
  begin
    b := (a + 1) mod 3;
    c := (a + 2) mod 3;
    ha := FFrame.Half[a];
    hb := FFrame.Half[b];
    hc := FFrame.Half[c];
    for si := 0 to 1 do
    begin
      if not FBoxBack[a, si] then
        Continue;
      side := (2 * si - 1) * ha;
      if TAlphaColorRec(FPaneColor).A > 0 then
      begin
        pb := TSkPathBuilder.Create;
        pb.MoveTo(FCam.Project(BoxPoint(a, side, b, -hb, c, -hc)));
        pb.LineTo(FCam.Project(BoxPoint(a, side, b, hb, c, -hc)));
        pb.LineTo(FCam.Project(BoxPoint(a, side, b, hb, c, hc)));
        pb.LineTo(FCam.Project(BoxPoint(a, side, b, -hb, c, hc)));
        pb.Close;
        ACanvas.DrawPath(pb.Detach, panePaint);
      end;
      // grid lines for the two in-plane axes
      inPlane[0] := b;
      inPlane[1] := c;
      for q := 0 to 1 do
      begin
        ax := inPlane[q];
        for k := 0 to High(FTicks[ax]) do
        begin
          t := FFrame.NormAxis(ax, FTicks[ax][k]);
          if ax = b then
            ACanvas.DrawLine(FCam.Project(BoxPoint(a, side, b, t, c, -hc)),
              FCam.Project(BoxPoint(a, side, b, t, c, hc)), gridPaint)
          else
            ACanvas.DrawLine(FCam.Project(BoxPoint(a, side, b, -hb, c, t)),
              FCam.Project(BoxPoint(a, side, b, hb, c, t)), gridPaint);
        end;
      end;
    end;
  end;
end;

procedure TRho3DPlot.DrawBoxEdges(const ACanvas: ISkCanvas; AFront: Boolean);
var
  a, b, c, ib, ic: Integer;
  front: Boolean;
  ha, hb, hc: Single;
  paint: ISkPaint;
begin
  if not FShowCube then
    Exit;
  paint := TSkPaint.Create(TSkPaintStyle.Stroke);
  paint.AntiAlias := True;
  paint.StrokeWidth := 1;
  paint.Color := FCubeColor;
  for a := 0 to 2 do
  begin
    b := (a + 1) mod 3;
    c := (a + 2) mod 3;
    ha := FFrame.Half[a];
    hb := FFrame.Half[b];
    hc := FFrame.Half[c];
    for ib := 0 to 1 do
      for ic := 0 to 1 do
      begin
        // an edge is in front only when both faces that meet there face us
        front := (not FBoxBack[b, ib]) and (not FBoxBack[c, ic]);
        if front <> AFront then
          Continue;
        ACanvas.DrawLine(
          FCam.Project(BoxPoint(a, -ha, b, (2 * ib - 1) * hb, c, (2 * ic - 1) * hc)),
          FCam.Project(BoxPoint(a, ha, b, (2 * ib - 1) * hb, c, (2 * ic - 1) * hc)),
          paint);
      end;
  end;
end;

procedure TRho3DPlot.DrawTextCentered(const ACanvas: ISkCanvas; const AText: string;
  const ACenter: TPointF; const AFont: ISkFont; const APaint: ISkPaint);
var
  w: Single;
begin
  if AText = '' then
    Exit;
  w := AFont.MeasureText(AText);
  ACanvas.DrawSimpleText(AText, ACenter.X - w / 2, ACenter.Y + AFont.Size * 0.36,
    AFont, APaint);
end;

procedure TRho3DPlot.DrawAxis(const ACanvas: ISkCanvas; A: Integer);
var
  b, c, ib, ic, bestB, bestC, k, skip: Integer;
  ha, hb, hc, vb, vc: Single;
  s0, s1, m, ctr, e, u, sp, tp: TPointF;
  score, best, len, spacing, h, ext, maxExt, maxW, dotUE: Single;
  labels: TArray<string>;
  widths: TArray<Single>;
  axisPaint, textPaint: ISkPaint;
  title: string;
  tw: Single;
begin
  b := (A + 1) mod 3;
  c := (A + 2) mod 3;
  ha := FFrame.Half[A];
  hb := FFrame.Half[b];
  hc := FFrame.Half[c];
  // an axis seen nearly end-on (z from the top, y from the front) gets no
  // ticks or labels: they would pile up in a corner
  if Abs(FCam.RotateVec(BoxPoint(A, 1, b, 0, c, 0)).Z) > 0.95 then
    Exit;
  // choose the edge on the outline: lowest on screen for x / y, leftmost for z
  best := -MaxSingle;
  bestB := 0;
  bestC := 0;
  for ib := 0 to 1 do
    for ic := 0 to 1 do
    begin
      vb := (2 * ib - 1) * hb;
      vc := (2 * ic - 1) * hc;
      s0 := FCam.Project(BoxPoint(A, -ha, b, vb, c, vc));
      s1 := FCam.Project(BoxPoint(A, ha, b, vb, c, vc));
      m := (s0 + s1) * 0.5;
      if A = 2 then
        score := -m.X
      else
        score := m.Y;
      // tie-break toward the nearer edge
      score := score + FCam.ToView(BoxPoint(A, 0, b, vb, c, vc)).Z * 0.01;
      if score > best then
      begin
        best := score;
        bestB := ib;
        bestC := ic;
      end;
    end;
  vb := (2 * bestB - 1) * hb;
  vc := (2 * bestC - 1) * hc;
  s0 := FCam.Project(BoxPoint(A, -ha, b, vb, c, vc));
  s1 := FCam.Project(BoxPoint(A, ha, b, vb, c, vc));
  len := s0.Distance(s1);
  if len < 20 then
    Exit;   // seen end-on: labels would pile up
  e := (s1 - s0) / len;
  m := (s0 + s1) * 0.5;
  ctr := FCam.Project(TPoint3D.Create(0, 0, 0));
  u := m - ctr;
  dotUE := u.X * e.X + u.Y * e.Y;
  u := u - e * dotUE;
  if u.Length < 1E-3 then
    u := TPointF.Create(-e.Y, e.X)
  else
    u := u / u.Length;

  axisPaint := TSkPaint.Create(TSkPaintStyle.Stroke);
  axisPaint.AntiAlias := True;
  axisPaint.Color := FAxisColor;
  axisPaint.StrokeWidth := 1.2;
  textPaint := TSkPaint.Create(TSkPaintStyle.Fill);
  textPaint.AntiAlias := True;
  textPaint.Color := FTextColor;

  ACanvas.DrawLine(s0, s1, axisPaint);

  h := FFontTick.Size;
  maxExt := 0;
  SetLength(labels, Length(FTicks[A]));
  SetLength(widths, Length(FTicks[A]));
  maxW := 0;
  for k := 0 to High(FTicks[A]) do
  begin
    if FTickText[A] <> nil then
      labels[k] := FTickText[A][k]
    else
      labels[k] := FormatTick(FTicks[A][k], FTickStep[A]);
    widths[k] := FFontTick.MeasureText(labels[k]);
    maxW := Max(maxW, widths[k]);
  end;
  // thin the labels if they would overlap along the edge
  skip := 1;
  if Length(FTicks[A]) > 1 then
  begin
    spacing := len * FTickStep[A] / (FFrame.Hi[A] - FFrame.Lo[A]);
    if spacing > 0 then
      skip := Max(1, Ceil((maxW * Abs(e.X) + h * Abs(e.Y) + 6) / spacing));
  end;
  for k := 0 to High(FTicks[A]) do
  begin
    sp := FCam.Project(BoxPoint(A, FFrame.NormAxis(A, FTicks[A][k]), b, vb, c, vc));
    if FShowTicks then
      ACanvas.DrawLine(sp, sp + u * 5, axisPaint);
    if FShowValues and (k mod skip = 0) then
    begin
      ext := Abs(u.X) * widths[k] / 2 + Abs(u.Y) * h / 2;
      maxExt := Max(maxExt, ext);
      tp := sp + u * (8 + ext);
      DrawTextCentered(ACanvas, labels[k], tp, FFontTick, textPaint);
    end;
  end;
  title := GetAxisTitle(A);
  if title <> '' then
  begin
    tw := FFontTitle[A].MeasureText(title);
    ext := Abs(u.X) * tw / 2 + Abs(u.Y) * FFontTitle[A].Size / 2;
    tp := m + u * (10 + 2 * maxExt + 4 + ext);
    DrawTextCentered(ACanvas, title, tp, FFontTitle[A], textPaint);
  end;
end;

{ ==================================================================== }
{ Colour bar, legend, title, hover                                       }
{ ==================================================================== }

function TRho3DPlot.ColorBarSeries: TRho3DSeries;
var
  s: TRho3DSeries;
begin
  Result := nil;
  if not FShowColorBar then
    Exit;
  // prefer a visible series, but keep the bar (and so the layout) while a
  // colour-mapped series is hidden from the legend, so nothing jumps
  for s in FSeries do
    if s.IsColorMapped then
    begin
      if s.FVisible then
        Exit(s);
      if Result = nil then
        Result := s;
    end;
end;

procedure TRho3DPlot.DrawColorBar(const ACanvas: ISkCanvas; const APlotRect: TRectF;
  S: TRho3DSeries);
const
  Slices = 96;
var
  bar: TRectF;
  i: Integer;
  y0, y1, step, v, y: Single;
  ticks: TArray<Double>;
  tstep: Double;
  fill, stroke, textPaint: ISkPaint;
  lbl: string;
begin
  bar := TRectF.Create(APlotRect.Right + 18, APlotRect.Top + APlotRect.Height * 0.2,
    APlotRect.Right + 32, APlotRect.Top + APlotRect.Height * 0.8);
  if bar.Height < 20 then
    Exit;
  fill := TSkPaint.Create(TSkPaintStyle.Fill);
  fill.AntiAlias := False;
  step := bar.Height / Slices;
  for i := 0 to Slices - 1 do
  begin
    y1 := bar.Bottom - i * step;
    y0 := y1 - step - 0.5;   // overlap a little to avoid seams
    fill.Color := ColorMapColor(S.FColorMap, (i + 0.5) / Slices);
    ACanvas.DrawRect(TRectF.Create(bar.Left, Max(y0, bar.Top), bar.Right, y1), fill);
  end;
  stroke := TSkPaint.Create(TSkPaintStyle.Stroke);
  stroke.AntiAlias := True;
  stroke.Color := FAxisColor;
  stroke.StrokeWidth := 1;
  ACanvas.DrawRect(bar, stroke);
  textPaint := TSkPaint.Create(TSkPaintStyle.Fill);
  textPaint.AntiAlias := True;
  textPaint.Color := FTextColor;
  ticks := NiceTicks(FCLo, FCHi, 5, tstep);
  for i := 0 to High(ticks) do
  begin
    v := (ticks[i] - FCLo) / (FCHi - FCLo);
    y := bar.Bottom - v * bar.Height;
    ACanvas.DrawLine(PointF(bar.Right, y), PointF(bar.Right + 4, y), stroke);
    lbl := FormatTick(ticks[i], tstep);
    ACanvas.DrawSimpleText(lbl, bar.Right + 7, y + FFontTick.Size * 0.36, FFontTick, textPaint);
  end;
  if FColorBarTitle <> '' then
    DrawTextCentered(ACanvas, FColorBarTitle,
      PointF(bar.CenterPoint.X, bar.Top - 14), FFontTick, textPaint);
end;

procedure TRho3DPlot.DrawLegend(const ACanvas: ISkCanvas; const APlotRect: TRectF);
const
  RowH = 18;
  Pad = 7;
  SwatchW = 26;
var
  rows: TList<Integer>;
  i, k, r: Integer;
  s: TRho3DSeries;
  w, h, maxW, x, y, cy: Single;
  rect, row: TRectF;
  bg, border, textPaint, linePaint, fill: ISkPaint;
  c: TAlphaColor;
begin
  rows := TList<Integer>.Create;
  try
    maxW := 0;
    for i := 0 to FSeries.Count - 1 do
    begin
      s := FSeries[i];
      if (s.FTitle <> '') and s.FShowInLegend then
      begin
        rows.Add(i);
        maxW := Max(maxW, FFontTick.MeasureText(s.FTitle));
      end;
    end;
    if FScreenPass then
    begin
      FLegendRect := TRectF.Empty;
      SetLength(FLegendRows, 0);
      SetLength(FLegendRowSeries, 0);
    end;
    if rows.Count = 0 then
      Exit;
    w := Pad * 2 + SwatchW + 6 + maxW;
    h := Pad * 2 + rows.Count * RowH;
    case FLegendLocation of
      llTopLeft:     begin x := APlotRect.Left + 10;      y := APlotRect.Top + 10; end;
      llBottomRight: begin x := APlotRect.Right - w - 10; y := APlotRect.Bottom - h - 10; end;
      llBottomLeft:  begin x := APlotRect.Left + 10;      y := APlotRect.Bottom - h - 10; end;
    else
      x := APlotRect.Right - w - 10;
      y := APlotRect.Top + 10;
    end;
    rect := TRectF.Create(x, y, x + w, y + h);
    rect.Offset(FLegendOffset);

    bg := TSkPaint.Create(TSkPaintStyle.Fill);
    bg.AntiAlias := True;
    bg.Color := (FBackgroundColor and $00FFFFFF) or $E6000000;
    ACanvas.DrawRoundRect(rect, 4, 4, bg);
    border := TSkPaint.Create(TSkPaintStyle.Stroke);
    border.AntiAlias := True;
    border.Color := FCubeColor;
    border.StrokeWidth := 1;
    ACanvas.DrawRoundRect(rect, 4, 4, border);
    textPaint := TSkPaint.Create(TSkPaintStyle.Fill);
    textPaint.AntiAlias := True;
    textPaint.Color := FTextColor;
    linePaint := TSkPaint.Create(TSkPaintStyle.Stroke);
    linePaint.AntiAlias := True;
    fill := TSkPaint.Create(TSkPaintStyle.Fill);
    fill.AntiAlias := True;

    if FScreenPass then
    begin
      FLegendRect := rect;
      SetLength(FLegendRows, rows.Count);
      SetLength(FLegendRowSeries, rows.Count);
    end;
    for r := 0 to rows.Count - 1 do
    begin
      s := FSeries[rows[r]];
      row := TRectF.Create(rect.Left, rect.Top + Pad + r * RowH, rect.Right,
        rect.Top + Pad + (r + 1) * RowH);
      if FScreenPass then
      begin
        FLegendRows[r] := row;
        FLegendRowSeries[r] := rows[r];
      end;
      cy := row.CenterPoint.Y;
      if not s.FVisible then
        ACanvas.SaveLayerAlpha(80);
      x := row.Left + Pad;
      if s.IsSurface or s.IsBars then
      begin
        if s.IsColorMapped then
          for k := 0 to 7 do
          begin
            fill.Color := ColorMapColor(s.FColorMap, (k + 0.5) / 8);
            ACanvas.DrawRect(TRectF.Create(x + k * SwatchW / 8, cy - 6,
              x + (k + 1) * SwatchW / 8 + 0.5, cy + 6), fill);
          end
        else
        begin
          fill.Color := s.FColor;
          ACanvas.DrawRect(TRectF.Create(x, cy - 6, x + SwatchW, cy + 6), fill);
        end;
        linePaint.Color := FCubeColor;
        linePaint.StrokeWidth := 1;
        ACanvas.DrawRect(TRectF.Create(x, cy - 6, x + SwatchW, cy + 6), linePaint);
      end
      else
      begin
        if (s.FKind = skCurve) and s.FShowLine then
        begin
          linePaint.StrokeWidth := Min(s.FThickness, 4);
          if s.IsColorMapped then
          begin
            for k := 0 to 3 do
            begin
              linePaint.Color := ColorMapColor(s.FColorMap, k / 3);
              ACanvas.DrawLine(PointF(x + k * SwatchW / 4, cy),
                PointF(x + (k + 1) * SwatchW / 4, cy), linePaint);
            end;
          end
          else if s.FUseGradient then
          begin
            linePaint.Color := s.FGradientStartColor;
            ACanvas.DrawLine(PointF(x, cy), PointF(x + SwatchW / 2, cy), linePaint);
            linePaint.Color := s.FGradientEndColor;
            ACanvas.DrawLine(PointF(x + SwatchW / 2, cy), PointF(x + SwatchW, cy), linePaint);
          end
          else
          begin
            linePaint.Color := s.FColor;
            ACanvas.DrawLine(PointF(x, cy), PointF(x + SwatchW, cy), linePaint);
          end;
        end;
        if (s.FKind = skScatter) or s.FShowPoints then
        begin
          if s.IsColorMapped then
            c := ColorMapColor(s.FColorMap, 0.5)
          else
            c := s.FColor;
          DrawMarker(ACanvas, PointF(x + SwatchW / 2, cy), Min(s.FPointSize, 10),
            s.FMarkerShape, c);
        end;
      end;
      ACanvas.DrawSimpleText(s.FTitle, x + SwatchW + 6, cy + FFontTick.Size * 0.36,
        FFontTick, textPaint);
      if not s.FVisible then
        ACanvas.Restore;
    end;
  finally
    rows.Free;
  end;
end;

procedure TRho3DPlot.DrawTitle(const ACanvas: ISkCanvas; const ADest: TRectF);
var
  paint: ISkPaint;
begin
  paint := TSkPaint.Create(TSkPaintStyle.Fill);
  paint.AntiAlias := True;
  paint.Color := FTextColor;
  DrawTextCentered(ACanvas, FChartTitle,
    PointF(ADest.CenterPoint.X, ADest.Top + FChartTitleFontSize + 1), FFontChart, paint);
end;

procedure TRho3DPlot.DrawHover(const ACanvas: ISkCanvas; const ADest: TRectF);
var
  s: TRho3DSeries;
  p: TPointF;
  dp: TRho3DDataPoint;
  lines: TArray<string>;
  i: Integer;
  w, h, lh: Single;
  box: TRectF;
  paint, textPaint: ISkPaint;
  v: Double;
begin
  if (FHoverSeries < 0) or (FHoverSeries >= FSeries.Count) then
    Exit;
  s := FSeries[FHoverSeries];
  if (FHoverIndex < 0) or (FHoverIndex >= Length(s.FScr)) or
     (FHoverIndex >= s.Count) or not IsFinitePt(s.FScr[FHoverIndex]) then
    Exit;
  p := s.FScr[FHoverIndex];
  dp := s.PointAt(FHoverIndex);
  lines := nil;
  if s.FTitle <> '' then
    lines := lines + [s.FTitle];
  lines := lines + [Format('%s = %.6g', [StrOr(FAxisTitleX, 'x'), dp.X]),
    Format('%s = %.6g', [StrOr(FAxisTitleY, 'y'), dp.Y]),
    Format('%s = %.6g', [StrOr(FAxisTitleZ, 'z'), dp.Z])];
  if s.IsColorMapped then
  begin
    v := s.ValueAt(FHoverIndex);
    if not IsNan(v) then
      lines := lines + [Format('%s = %.6g',
        [StrOr(FColorBarTitle, 'value'), v])];
  end;

  paint := TSkPaint.Create(TSkPaintStyle.Stroke);
  paint.AntiAlias := True;
  paint.StrokeWidth := 1.5;
  paint.Color := FTextColor;
  ACanvas.DrawCircle(p, 5, paint);

  lh := FFontTick.Size + 4;
  w := 0;
  for i := 0 to High(lines) do
    w := Max(w, FFontTick.MeasureText(lines[i]));
  w := w + 12;
  h := Length(lines) * lh + 8;
  box := TRectF.Create(p.X + 12, p.Y + 12, p.X + 12 + w, p.Y + 12 + h);
  if box.Right > ADest.Right - 2 then
    box.Offset(-(w + 24), 0);
  if box.Bottom > ADest.Bottom - 2 then
    box.Offset(0, -(h + 24));
  paint := TSkPaint.Create(TSkPaintStyle.Fill);
  paint.AntiAlias := True;
  paint.Color := (FBackgroundColor and $00FFFFFF) or $F0000000;
  ACanvas.DrawRoundRect(box, 4, 4, paint);
  paint.Style := TSkPaintStyle.Stroke;
  paint.Color := FAxisColor;
  paint.StrokeWidth := 1;
  ACanvas.DrawRoundRect(box, 4, 4, paint);
  textPaint := TSkPaint.Create(TSkPaintStyle.Fill);
  textPaint.AntiAlias := True;
  textPaint.Color := FTextColor;
  for i := 0 to High(lines) do
    ACanvas.DrawSimpleText(lines[i], box.Left + 6, box.Top + 4 + (i + 1) * lh - 4,
      FFontTick, textPaint);
end;

{ ==================================================================== }
{ Render                                                                }
{ ==================================================================== }

procedure TRho3DPlot.RenderScene(const ACanvas: ISkCanvas; const ADest: TRectF;
  const AClearColor: TAlphaColor; AOverlay: Boolean; AVector: Boolean);
var
  plotRect: TRectF;
  cbSeries: TRho3DSeries;
  s: TRho3DSeries;
  a: Integer;
  laz, lel: Double;
begin
  ACanvas.Clear(AClearColor);
  Prepare;

  if FFontTick = nil then
  begin
    FFontTick := TSkFont.Create(nil, FTickFontSize);
    for a := 0 to 2 do
      FFontTitle[a] := TSkFont.Create(nil, FAxisTitleFontSize[a]);
    FFontChart := TSkFont.Create(TSkTypeface.MakeFromName('', TSkFontStyle.Bold),
      FChartTitleFontSize);
  end;

  plotRect := ADest;
  if FChartTitle <> '' then
    plotRect.Top := plotRect.Top + Max(30, 2 * FChartTitleFontSize);
  cbSeries := ColorBarSeries;
  if cbSeries <> nil then
    plotRect.Right := plotRect.Right - 80;
  if (plotRect.Width < 10) or (plotRect.Height < 10) then
    Exit;

  FCam.Prepare(plotRect);
  if FScreenPass then
  begin
    FScreenCenter := FCam.Center;
    FScreenMinWH := FCam.MinWH;
  end;
  laz := FLightAzimuth * Pi / 180;
  lel := FLightElevation * Pi / 180;
  FLightVec := TPoint3D.Create(Sin(laz) * Cos(lel), Sin(lel), Cos(laz) * Cos(lel));
  for a := 0 to 2 do
    ComputeTicks(a);

  for s in FSeries do
    if s.FVisible then
      TransformSeries(s);

  ComputeBoxFacing;
  DrawBoxBack(ACanvas);
  DrawBoxEdges(ACanvas, False);
  DrawScene(ACanvas, AVector);
  DrawBoxEdges(ACanvas, True);
  if FShowAxes then
    for a := 0 to 2 do
      DrawAxis(ACanvas, a);
  if cbSeries <> nil then
    DrawColorBar(ACanvas, plotRect, cbSeries);
  if FLegendVisible then
    DrawLegend(ACanvas, plotRect)
  else if FScreenPass then
    FLegendRect := TRectF.Empty;
  if FChartTitle <> '' then
    DrawTitle(ACanvas, ADest);
  if AOverlay and FShowHoverInfo and not FPressed then
    DrawHover(ACanvas, ADest);
end;

function TRho3DPlot.GetSceneScale: Single;
begin
  if Scene <> nil then
    Result := Scene.GetSceneScale
  else
    Result := 1;
end;

procedure TRho3DPlot.Draw(const ACanvas: ISkCanvas; const ADest: TRectF;
  const AOpacity: Single);
var
  scale: Single;
  pw, ph: Integer;
  img: ISkImage;
begin
  // Render at physical resolution into an offscreen surface (in logical
  // units through a scale), then draw it 1:1, as the 2D component does, so
  // lines and text stay sharp on HiDPI / Retina.
  scale := GetSceneScale;
  pw := Round(ADest.Width * scale);
  ph := Round(ADest.Height * scale);
  if (pw <= 0) or (ph <= 0) then
    Exit;
  if (FSurface = nil) or (FSurfaceW <> pw) or (FSurfaceH <> ph) then
  begin
    FSurface := TSkSurface.MakeRaster(pw, ph);
    FSurfaceW := pw;
    FSurfaceH := ph;
  end;
  FScreenPass := True;
  try
    if FSurface = nil then
    begin
      RenderScene(ACanvas, ADest, FBackgroundColor, True);
      Exit;
    end;
    FSurface.Canvas.Save;
    try
      FSurface.Canvas.Scale(scale, scale);
      RenderScene(FSurface.Canvas, TRectF.Create(0, 0, ADest.Width, ADest.Height),
        FBackgroundColor, True);
    finally
      FSurface.Canvas.Restore;
    end;
  finally
    FScreenPass := False;
  end;
  img := FSurface.MakeImageSnapshot;
  if img <> nil then
    ACanvas.DrawImageRect(img, TRectF.Create(0, 0, pw, ph), ADest,
      TSkSamplingOptions.Create(TSkFilterMode.Nearest, TSkMipmapMode.None));
end;

{ ==================================================================== }
{ Export                                                                }
{ ==================================================================== }

function TRho3DPlot.MakeImage(AWidth, AHeight: Integer; ATransparent: Boolean): ISkImage;
var
  surface: ISkSurface;
  scale, lw, lh: Single;
  clear: TAlphaColor;
begin
  if (AWidth <= 0) or (AHeight <= 0) then
  begin
    scale := GetSceneScale;
    AWidth := Round(Width * scale);
    AHeight := Round(Height * scale);
  end
  else if (Width > 0) and (Height > 0) then
    scale := Min(AWidth / Width, AHeight / Height)
  else
    scale := 1;
  if (AWidth <= 0) or (AHeight <= 0) or (scale <= 0) then
    raise Exception.Create('TRho3DPlot: invalid image size');
  lw := AWidth / scale;
  lh := AHeight / scale;
  if ATransparent then
    clear := TAlphaColors.Null
  else
    clear := FBackgroundColor;
  surface := TSkSurface.MakeRaster(AWidth, AHeight);
  if surface = nil then
    raise Exception.Create('TRho3DPlot: could not create image surface');
  surface.Canvas.Scale(scale, scale);
  RenderScene(surface.Canvas, TRectF.Create(0, 0, lw, lh), clear, False);
  Result := surface.MakeImageSnapshot;
  Redraw;   // refresh the on-screen hit-test state
end;

procedure TRho3DPlot.SaveToPNG(const AFileName: string; AWidth, AHeight: Integer;
  ATransparent: Boolean);
var
  image: ISkImage;
begin
  image := MakeImage(AWidth, AHeight, ATransparent);
  image.EncodeToFile(AFileName, TSkEncodedImageFormat.PNG);
end;

procedure TRho3DPlot.RenderTo(const ACanvas: ISkCanvas; const ADest: TRectF);
begin
  ACanvas.Save;
  try
    // Clipped to ADest, so clearing the background leaves the rest of the
    // canvas (other charts drawn on it) alone.
    ACanvas.ClipRect(ADest);
    ACanvas.Translate(ADest.Left, ADest.Top);
    RenderScene(ACanvas, TRectF.Create(0, 0, ADest.Width, ADest.Height), FBackgroundColor,
      False, True);
  finally
    ACanvas.Restore;
  end;
  Redraw;
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
    metadata := TSkPDFMetadata.Create(StrOr(FChartTitle, '3D Plot'),
      '', '', '', 'TRho3DPlot');
    document := TSkDocument.MakePDF(stream, metadata);
    try
      canvas := document.BeginPage(AWidth, AHeight);
      RenderScene(canvas, TRectF.Create(0, 0, AWidth, AHeight), FBackgroundColor,
        False, True);
      document.EndPage;
    finally
      document.Close;
    end;
  finally
    stream.Free;
  end;
  Redraw;
end;

procedure TRho3DPlot.CopyToClipboard;
var
  image: ISkImage;
  bmp: TBitmap;
  svc: IFMXClipboardService;
begin
  image := MakeImage(0, 0, False);
  if image = nil then
    Exit;
  bmp := SkImageToBitmap(image);
  try
    if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, svc) then
      svc.SetClipboard(TValue.From<TBitmap>(bmp));
  finally
    bmp.Free;
  end;
end;

{ ==================================================================== }
{ JSON                                                                  }
{ ==================================================================== }

function TRho3DPlot.SaveToJson: TJSONObject;
var
  o, ser, t: TJSONObject;
  arr, names: TJSONArray;
  s: TRho3DSeries;
  i, k: Integer;
begin
  Result := TJSONObject.Create;
  try
    JPutStr(Result, 'format', 'Rho3DPlot');
    JPutInt(Result, 'version', Rho3DJsonVersion);

    o := TJSONObject.Create;
    Result.AddPair('view', o);
    JPutFloat(o, 'azimuth', FCam.Azimuth);
    JPutFloat(o, 'elevation', FCam.Elevation);
    JPutFloat(o, 'zoom', FCam.Zoom);
    JPutFloat(o, 'panX', FCam.PanX);
    JPutFloat(o, 'panY', FCam.PanY);
    JPutStr(o, 'projection', ProjectionNames[FCam.Projection]);

    o := TJSONObject.Create;
    Result.AddPair('chart', o);
    JPutStr(o, 'title', FChartTitle);
    JPutFloat(o, 'tickFontSize', FTickFontSize);
    JPutFloat(o, 'axisTitleFontSizeX', FAxisTitleFontSize[0]);
    JPutFloat(o, 'axisTitleFontSizeY', FAxisTitleFontSize[1]);
    JPutFloat(o, 'axisTitleFontSizeZ', FAxisTitleFontSize[2]);
    JPutFloat(o, 'titleFontSize', FChartTitleFontSize);
    JPutStr(o, 'theme', ThemeNames[FTheme]);
    JPutColor(o, 'background', FBackgroundColor);
    JPutColor(o, 'box', FCubeColor);
    JPutColor(o, 'axis', FAxisColor);
    JPutColor(o, 'text', FTextColor);
    JPutColor(o, 'grid', FGridColor);
    JPutColor(o, 'pane', FPaneColor);
    JPutBool(o, 'depthCue', FDepthCue);
    JPutBool(o, 'showHoverInfo', FShowHoverInfo);

    o := TJSONObject.Create;
    Result.AddPair('axes', o);
    JPutStr(o, 'titleX', FAxisTitleX);
    JPutStr(o, 'titleY', FAxisTitleY);
    JPutStr(o, 'titleZ', FAxisTitleZ);
    JPutBool(o, 'showBox', FShowCube);
    JPutBool(o, 'showAxes', FShowAxes);
    JPutBool(o, 'showTicks', FShowTicks);
    JPutBool(o, 'showValues', FShowValues);
    JPutBool(o, 'showGrid', FShowGrid);
    JPutInt(o, 'tickCount', FTickCount);
    JPutStr(o, 'aspect', AspectNames[FAspect]);
    JPutVector(o, 'aspectRatio', [FAspectRatio[0], FAspectRatio[1], FAspectRatio[2]]);
    JPutVector(o, 'limits', [FLimits[0], FLimits[1], FLimits[2], FLimits[3], FLimits[4], FLimits[5]]);
    JPutBool(o, 'fixedBounds', FUseFixedBounds);
    if FUseFixedBounds then
    begin
      JPutVector(o, 'fixedMin', [FFixedMin.X, FFixedMin.Y, FFixedMin.Z]);
      JPutVector(o, 'fixedMax', [FFixedMax.X, FFixedMax.Y, FFixedMax.Z]);
    end;
    // named ticks: {positions, labels} per axis, empty for round numbers
    for i := 0 to 2 do
    begin
      t := TJSONObject.Create;
      o.AddPair(TickLabelKeys[i], t);
      JPutVector(t, 'positions', FTickPos[i]);
      names := TJSONArray.Create;
      for k := 0 to High(FTickNames[i]) do
        names.Add(FTickNames[i][k]);
      t.AddPair('labels', names);
    end;

    o := TJSONObject.Create;
    Result.AddPair('colorBar', o);
    JPutBool(o, 'show', FShowColorBar);
    JPutStr(o, 'title', FColorBarTitle);
    JPutFloat(o, 'min', FColorMin);
    JPutFloat(o, 'max', FColorMax);

    o := TJSONObject.Create;
    Result.AddPair('lighting', o);
    JPutFloat(o, 'azimuth', FLightAzimuth);
    JPutFloat(o, 'elevation', FLightElevation);
    JPutFloat(o, 'ambient', FAmbient);

    o := TJSONObject.Create;
    Result.AddPair('legend', o);
    JPutBool(o, 'visible', FLegendVisible);
    JPutStr(o, 'location', LegendLocationNames[FLegendLocation]);
    JPutFloat(o, 'offsetX', FLegendOffset.X);
    JPutFloat(o, 'offsetY', FLegendOffset.Y);

    o := TJSONObject.Create;
    Result.AddPair('animation', o);
    JPutFloat(o, 'revealFraction', FRevealFraction);
    JPutBool(o, 'showRevealHead', FShowRevealHead);
    JPutBool(o, 'autoRotate', FAutoRotate);
    JPutFloat(o, 'autoRotateSpeed', FAutoRotateSpeed);

    o := TJSONObject.Create;
    Result.AddPair('style', o);
    JPutColor(o, 'lineColor', FLineColor);
    JPutFloat(o, 'lineThickness', FLineThickness);
    JPutBool(o, 'useGradient', FUseGradient);
    JPutColor(o, 'gradientStart', FGradientStartColor);
    JPutColor(o, 'gradientEnd', FGradientEndColor);
    JPutBool(o, 'showLines', FShowLines);
    JPutBool(o, 'showPoints', FShowPoints);
    JPutFloat(o, 'pointSize', FPointSize);

    arr := TJSONArray.Create;
    Result.AddPair('series', arr);
    for s in FSeries do
    begin
      ser := TJSONObject.Create;
      arr.AddElement(ser);
      s.SaveToJson(ser);
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure TRho3DPlot.LoadFromJson(const AObj: TJSONObject);
var
  o, t: TJSONObject;
  arr: TJSONArray;
  v: TArray<Double>;
  lbls: TArray<string>;
  i, k: Integer;
  s: TRho3DSeries;
begin
  if AObj = nil then
    Exit;
  // a newer version is loaded as far as it is understood (unknown keys are ignored)
  StopReveal;

  o := JObj(AObj, 'view');
  FCam.Azimuth := JFloat(o, 'azimuth', FCam.Azimuth);
  FCam.Elevation := EnsureRange(JFloat(o, 'elevation', FCam.Elevation), -90, 90);
  FCam.Zoom := EnsureRange(JFloat(o, 'zoom', FCam.Zoom), 0.05, 100);
  FCam.PanX := JFloat(o, 'panX', FCam.PanX);
  FCam.PanY := JFloat(o, 'panY', FCam.PanY);
  FCam.Projection := TRho3DProjection(NameIndex(ProjectionNames,
    JStr(o, 'projection', ''), Ord(FCam.Projection)));

  o := JObj(AObj, 'chart');
  FChartTitle := JStr(o, 'title', FChartTitle);
  FTickFontSize := JFloat(o, 'tickFontSize', FTickFontSize);
  FAxisTitleFontSize[0] := JFloat(o, 'axisTitleFontSizeX',
    JFloat(o, 'axisTitleFontSize', FAxisTitleFontSize[0]));
  FAxisTitleFontSize[1] := JFloat(o, 'axisTitleFontSizeY',
    JFloat(o, 'axisTitleFontSize', FAxisTitleFontSize[1]));
  FAxisTitleFontSize[2] := JFloat(o, 'axisTitleFontSizeZ',
    JFloat(o, 'axisTitleFontSize', FAxisTitleFontSize[2]));
  FChartTitleFontSize := JFloat(o, 'titleFontSize', FChartTitleFontSize);
  FFontTick := nil;
  FFontTitle[0] := nil;
  FFontTitle[1] := nil;
  FFontTitle[2] := nil;
  FFontChart := nil;
  FTheme := TRho3DTheme(NameIndex(ThemeNames, JStr(o, 'theme', ''), Ord(FTheme)));
  FBackgroundColor := JColor(o, 'background', FBackgroundColor);
  FCubeColor := JColor(o, 'box', FCubeColor);
  FAxisColor := JColor(o, 'axis', FAxisColor);
  FTextColor := JColor(o, 'text', FTextColor);
  FGridColor := JColor(o, 'grid', FGridColor);
  FPaneColor := JColor(o, 'pane', FPaneColor);
  FDepthCue := JBool(o, 'depthCue', FDepthCue);
  FShowHoverInfo := JBool(o, 'showHoverInfo', FShowHoverInfo);

  o := JObj(AObj, 'axes');
  FAxisTitleX := JStr(o, 'titleX', FAxisTitleX);
  FAxisTitleY := JStr(o, 'titleY', FAxisTitleY);
  FAxisTitleZ := JStr(o, 'titleZ', FAxisTitleZ);
  FShowCube := JBool(o, 'showBox', FShowCube);
  FShowAxes := JBool(o, 'showAxes', FShowAxes);
  FShowTicks := JBool(o, 'showTicks', FShowTicks);
  FShowValues := JBool(o, 'showValues', FShowValues);
  FShowGrid := JBool(o, 'showGrid', FShowGrid);
  FTickCount := Max(1, JInt(o, 'tickCount', FTickCount));
  FAspect := TRho3DAspect(NameIndex(AspectNames, JStr(o, 'aspect', ''), Ord(FAspect)));
  v := JVector(o, 'aspectRatio');
  if Length(v) = 3 then
    for i := 0 to 2 do
      if not IsNan(v[i]) then
        FAspectRatio[i] := v[i];
  v := JVector(o, 'limits');
  if Length(v) = 6 then
    for i := 0 to 5 do
      FLimits[i] := v[i];
  FUseFixedBounds := JBool(o, 'fixedBounds', False);
  if FUseFixedBounds then
  begin
    v := JVector(o, 'fixedMin');
    if Length(v) = 3 then FFixedMin := TPoint3D.Create(v[0], v[1], v[2]);
    v := JVector(o, 'fixedMax');
    if Length(v) = 3 then FFixedMax := TPoint3D.Create(v[0], v[1], v[2]);
  end;
  for i := 0 to 2 do
  begin
    t := JObj(o, TickLabelKeys[i]);
    if t <> nil then
    begin
      v := JVector(t, 'positions');
      lbls := nil;
      if t.GetValue('labels') is TJSONArray then
        for k := 0 to TJSONArray(t.GetValue('labels')).Count - 1 do
          lbls := lbls + [TJSONArray(t.GetValue('labels')).Items[k].Value];
      if Length(lbls) = Length(v) then
      begin
        FTickPos[i] := v;
        FTickNames[i] := lbls;
      end;
    end;
  end;

  o := JObj(AObj, 'colorBar');
  FShowColorBar := JBool(o, 'show', FShowColorBar);
  FColorBarTitle := JStr(o, 'title', FColorBarTitle);
  if o <> nil then
  begin
    FColorMin := JFloat(o, 'min', NaN);
    FColorMax := JFloat(o, 'max', NaN);
  end;

  o := JObj(AObj, 'lighting');
  FLightAzimuth := JFloat(o, 'azimuth', FLightAzimuth);
  FLightElevation := JFloat(o, 'elevation', FLightElevation);
  FAmbient := EnsureRange(JFloat(o, 'ambient', FAmbient), 0, 1);

  o := JObj(AObj, 'legend');
  FLegendVisible := JBool(o, 'visible', FLegendVisible);
  FLegendLocation := TRho3DLegendLocation(NameIndex(LegendLocationNames,
    JStr(o, 'location', ''), Ord(FLegendLocation)));
  FLegendOffset.X := JFloat(o, 'offsetX', FLegendOffset.X);
  FLegendOffset.Y := JFloat(o, 'offsetY', FLegendOffset.Y);

  o := JObj(AObj, 'animation');
  FRevealFraction := EnsureRange(JFloat(o, 'revealFraction', FRevealFraction), 0, 1);
  FShowRevealHead := JBool(o, 'showRevealHead', FShowRevealHead);
  FAutoRotateSpeed := JFloat(o, 'autoRotateSpeed', FAutoRotateSpeed);
  SetAutoRotate(JBool(o, 'autoRotate', FAutoRotate));

  o := JObj(AObj, 'style');
  FLineColor := JColor(o, 'lineColor', FLineColor);
  FLineThickness := JFloat(o, 'lineThickness', FLineThickness);
  FUseGradient := JBool(o, 'useGradient', FUseGradient);
  FGradientStartColor := JColor(o, 'gradientStart', FGradientStartColor);
  FGradientEndColor := JColor(o, 'gradientEnd', FGradientEndColor);
  FShowLines := JBool(o, 'showLines', FShowLines);
  FShowPoints := JBool(o, 'showPoints', FShowPoints);
  FPointSize := JFloat(o, 'pointSize', FPointSize);

  arr := JArr(AObj, 'series');
  if arr <> nil then
  begin
    FSeries.Clear;
    FHoverSeries := -1;
    for i := 0 to arr.Count - 1 do
      if arr.Items[i] is TJSONObject then
      begin
        s := AddSeries;
        s.LoadFromJson(TJSONObject(arr.Items[i]));
      end;
  end;
  SeriesChanged;
  ViewChanged;
end;

procedure TRho3DPlot.SavePlotToFile(const AFileName: string);
var
  obj: TJSONObject;
begin
  obj := SaveToJson;
  try
    // UTF-8 without a byte-order mark, which every JSON reader accepts
    TFile.WriteAllBytes(AFileName, TEncoding.UTF8.GetBytes(obj.Format(2)));
  finally
    obj.Free;
  end;
end;

procedure TRho3DPlot.LoadPlotFromFile(const AFileName: string);
var
  v: TJSONValue;
  bytes: TBytes;
  skip: Integer;
begin
  bytes := TFile.ReadAllBytes(AFileName);
  skip := 0;
  if (Length(bytes) >= 3) and (bytes[0] = $EF) and (bytes[1] = $BB) and (bytes[2] = $BF) then
    skip := 3;   // tolerate a byte-order mark
  v := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(bytes, skip, Length(bytes) - skip));
  try
    if not (v is TJSONObject) then
      raise Exception.CreateFmt('%s is not a Rho3DPlot JSON file', [AFileName]);
    LoadFromJson(TJSONObject(v));
  finally
    v.Free;
  end;
end;

{ ==================================================================== }
{ Picking and interaction                                               }
{ ==================================================================== }

function TRho3DPlot.DataToScreen(const AX, AY, AZ: Double; out P: TPointF): Boolean;
begin
  Prepare;
  Result := FScreenMinWH > 0;
  if Result then
    P := FCam.Project(FFrame.Normalize(AX, AY, AZ));
end;

function TRho3DPlot.FindNearestPoint(const X, Y: Single; out ASeries: TRho3DSeries;
  out AIndex: Integer): Boolean;
var
  si, i, n, last: Integer;
  s: TRho3DSeries;
  d, best, bestDepth, tol2: Single;
  p: TPointF;
begin
  ASeries := nil;
  AIndex := -1;
  tol2 := Sqr(FPickTolerance);
  best := MaxSingle;
  bestDepth := -MaxSingle;
  for si := 0 to FSeries.Count - 1 do
  begin
    s := FSeries[si];
    if not s.FVisible then
      Continue;
    n := Min(Length(s.FScr), s.Count);
    last := n - 1;
    if (s.FKind = skCurve) and (FRevealFraction < 1) then
      last := Min(last, RevealSegments(s));
    for i := 0 to last do
    begin
      p := s.FScr[i];
      if not IsFinitePt(p) then
        Continue;
      d := Sqr(p.X - X) + Sqr(p.Y - Y);
      if d > tol2 then
        Continue;
      // closest in pixels; among equals prefer the one nearer the viewer
      if (d < best - 0.25) or ((d <= best + 0.25) and (s.FDepth[i] > bestDepth)) then
      begin
        best := d;
        bestDepth := s.FDepth[i];
        ASeries := s;
        AIndex := i;
      end;
    end;
  end;
  Result := ASeries <> nil;
end;

procedure TRho3DPlot.UpdateHover(const X, Y: Single);
var
  s: TRho3DSeries;
  idx, si: Integer;
begin
  if not FShowHoverInfo then
    Exit;
  si := -1;
  if FindNearestPoint(X, Y, s, idx) then
    si := FSeries.IndexOf(s)
  else
    idx := -1;
  if (si <> FHoverSeries) or (idx <> FHoverIndex) then
  begin
    FHoverSeries := si;
    FHoverIndex := idx;
    Redraw;
  end;
end;

procedure TRho3DPlot.ZoomAbout(const P: TPointF; AFactor: Single);
var
  newZoom, f: Single;
  c, rectC, newC: TPointF;
begin
  newZoom := EnsureRange(FCam.Zoom * AFactor, 0.05, 100);
  f := newZoom / FCam.Zoom;
  if FScreenMinWH > 0 then
  begin
    c := FScreenCenter;
    rectC := c - TPointF.Create(FCam.PanX, FCam.PanY) * FScreenMinWH;
    newC := P - (P - c) * f;
    FCam.PanX := (newC.X - rectC.X) / FScreenMinWH;
    FCam.PanY := (newC.Y - rectC.Y) / FScreenMinWH;
  end;
  FCam.Zoom := newZoom;
  ViewChanged;
end;

procedure TRho3DPlot.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Single);
begin
  inherited;
  if CanFocus and not IsFocused then
    SetFocus;
  FCtrlDown := ssCtrl in Shift;
  FPressed := True;
  FMoved := False;
  FPressPos := PointF(X, Y);
  FLastPos := FPressPos;
  if (Button = TMouseButton.mbLeft) and not (ssShift in Shift) and FLegendVisible and
     FLegendRect.Contains(FPressPos) then
  begin
    FMode := imLegend;
    FLegendDragOrigin := FLegendOffset;
  end
  else if (Button = TMouseButton.mbRight) or
     ((Button = TMouseButton.mbLeft) and (ssShift in Shift)) then
    FMode := imPan
  else if Button = TMouseButton.mbLeft then
    FMode := imRotate
  else
    FMode := imNone;
end;

procedure TRho3DPlot.MouseMove(Shift: TShiftState; X, Y: Single);
var
  dx, dy: Single;
begin
  inherited;
  FMousePos := PointF(X, Y);
  if not FPressed then
  begin
    UpdateHover(X, Y);
    Exit;
  end;
  if not FMoved then
  begin
    if FPressPos.Distance(FMousePos) <= 3 then
      Exit;
    FMoved := True;
    FHoverSeries := -1;
    if FMode in [imRotate, imPan] then
      FInteracting := True;
  end;
  dx := X - FLastPos.X;
  dy := Y - FLastPos.Y;
  FLastPos := FMousePos;
  case FMode of
    imRotate:
      begin
        FCam.Azimuth := FCam.Azimuth - dx * 0.5;
        if FCam.Azimuth > 180 then FCam.Azimuth := FCam.Azimuth - 360;
        if FCam.Azimuth < -180 then FCam.Azimuth := FCam.Azimuth + 360;
        FCam.Elevation := EnsureRange(FCam.Elevation + dy * 0.5, -90, 90);
        ViewChanged;
      end;
    imPan:
      if FScreenMinWH > 0 then
      begin
        FCam.PanX := FCam.PanX + dx / FScreenMinWH;
        FCam.PanY := FCam.PanY + dy / FScreenMinWH;
        ViewChanged;
      end;
    imLegend:
      begin
        FLegendOffset := FLegendDragOrigin + (FMousePos - FPressPos);
        Redraw;
      end;
  end;
end;

procedure TRho3DPlot.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Single);
var
  wasMoved: Boolean;
  mode: TInteractMode;
  s: TRho3DSeries;
  idx, r: Integer;
  dp: TRho3DDataPoint;
begin
  inherited;
  wasMoved := FMoved;
  mode := FMode;
  FPressed := False;
  FMoved := False;
  FMode := imNone;
  if FInteracting then
  begin
    FInteracting := False;
    Redraw;   // back to full detail
  end;
  if wasMoved then
    Exit;
  if Button = TMouseButton.mbRight then
    ShowPlotMenu
  else if Button = TMouseButton.mbLeft then
  begin
    if mode = imLegend then
    begin
      for r := 0 to High(FLegendRows) do
        if FLegendRows[r].Contains(PointF(X, Y)) and
           (FLegendRowSeries[r] < FSeries.Count) then
        begin
          s := FSeries[FLegendRowSeries[r]];
          s.Visible := not s.Visible;
          Break;
        end;
    end
    else if Assigned(FOnPointPicked) and FindNearestPoint(X, Y, s, idx) then
    begin
      dp := s.PointAt(idx);
      FOnPointPicked(Self, s, idx, dp.X, dp.Y, dp.Z);
    end;
  end;
end;

procedure TRho3DPlot.MouseWheel(Shift: TShiftState; WheelDelta: Integer;
  var Handled: Boolean);
begin
  inherited;
  if WheelDelta > 0 then
    ZoomAbout(FMousePos, 1.1)
  else if WheelDelta < 0 then
    ZoomAbout(FMousePos, 1 / 1.1);
  Handled := True;
end;

procedure TRho3DPlot.DoMouseLeave;
begin
  inherited;
  if FHoverSeries >= 0 then
  begin
    FHoverSeries := -1;
    Redraw;
  end;
end;

procedure TRho3DPlot.DblClick;
var
  wasCtrl: Boolean;
begin
  inherited;
  wasCtrl := FCtrlDown;
  FCtrlDown := False;
  if wasCtrl then
    ResetView
  else
    ShowEditor;
end;

procedure TRho3DPlot.KeyDown(var Key: Word; var KeyChar: WideChar;
  Shift: TShiftState);
var
  c: TPointF;
begin
  inherited;
  c := FScreenCenter;
  case Key of
    vkLeft:  begin SetAzimuth(FCam.Azimuth + 5); Key := 0; end;
    vkRight: begin SetAzimuth(FCam.Azimuth - 5); Key := 0; end;
    vkUp:    begin SetElevation(FCam.Elevation + 5); Key := 0; end;
    vkDown:  begin SetElevation(FCam.Elevation - 5); Key := 0; end;
    vkAdd:      begin ZoomAbout(c, 1.1); Key := 0; KeyChar := #0; end;
    vkSubtract: begin ZoomAbout(c, 1 / 1.1); Key := 0; KeyChar := #0; end;
  end;
  case KeyChar of
    '+', '=': begin ZoomAbout(c, 1.1); KeyChar := #0; end;
    '-':      begin ZoomAbout(c, 1 / 1.1); KeyChar := #0; end;
    'r', 'R': begin ResetView; KeyChar := #0; end;
    '1': begin ViewPreset(vpIsometric); KeyChar := #0; end;
    '2': begin ViewPreset(vpTop); KeyChar := #0; end;
    '3': begin ViewPreset(vpFront); KeyChar := #0; end;
    '4': begin ViewPreset(vpSide); KeyChar := #0; end;
  end;
end;

{ ---- context menu ---- }

procedure TRho3DPlot.ShowPlotMenu;

  procedure AddItem(const AText: string; AHandler: TNotifyEvent);
  var
    item: TMenuItem;
  begin
    item := TMenuItem.Create(FMenu);
    item.Text := AText;
    item.OnClick := AHandler;
    FMenu.AddObject(item);
  end;

var
  pt: TPointF;
begin
  if FMenu = nil then
  begin
    FMenu := TPopupMenu.Create(Self);
    FMenu.Parent := Self;
    AddItem('Copy Image', MenuCopyImage);
    AddItem('Export PNG...', MenuExportPNG);
    AddItem('Export PDF...', MenuExportPDF);
    AddItem('-', nil);
    AddItem('Save Plot...', MenuSavePlot);
    AddItem('Load Plot...', MenuLoadPlot);
    AddItem('-', nil);
    AddItem('Reset View', MenuResetView);
    AddItem('Properties...', MenuProperties);
  end;
  pt := Screen.MousePos;
  FMenu.Popup(pt.X, pt.Y);
end;

function AskFileName(AOwner: TComponent; ASave: Boolean; const ATitle, AFilter,
  AExt, ADefault: string; out AFileName: string): Boolean;
var
  dlg: TOpenDialog;
begin
  if ASave then
    dlg := TSaveDialog.Create(AOwner)
  else
    dlg := TOpenDialog.Create(AOwner);
  try
    dlg.Title := ATitle;
    dlg.Filter := AFilter;
    dlg.DefaultExt := AExt;
    dlg.FileName := ADefault;
    if ASave then
      dlg.Options := dlg.Options + [TOpenOption.ofOverwritePrompt];
    Result := dlg.Execute;
    if Result then
    begin
      AFileName := dlg.FileName;
      if TPath.GetExtension(AFileName) = '' then
        AFileName := AFileName + '.' + AExt;
    end;
  finally
    dlg.Free;
  end;
end;

procedure TRho3DPlot.MenuCopyImage(Sender: TObject);
begin
  CopyToClipboard;
end;

procedure TRho3DPlot.MenuExportPNG(Sender: TObject);
var
  fn: string;
begin
  if AskFileName(Self, True, 'Export PNG', 'PNG image (*.png)|*.png', 'png',
    'plot3d.png', fn) then
    SaveToPNG(fn, Round(Width * 3), Round(Height * 3));
end;

procedure TRho3DPlot.MenuExportPDF(Sender: TObject);
var
  fn: string;
begin
  if AskFileName(Self, True, 'Export PDF', 'PDF document (*.pdf)|*.pdf', 'pdf',
    'plot3d.pdf', fn) then
    SaveToPDF(fn);
end;

procedure TRho3DPlot.MenuSavePlot(Sender: TObject);
var
  fn: string;
begin
  if AskFileName(Self, True, 'Save Plot', 'Plot JSON (*.json)|*.json', 'json',
    'plot3d.json', fn) then
    SavePlotToFile(fn);
end;

procedure TRho3DPlot.MenuLoadPlot(Sender: TObject);
var
  fn: string;
begin
  if AskFileName(Self, False, 'Load Plot', 'Plot JSON (*.json)|*.json', 'json',
    '', fn) then
    LoadPlotFromFile(fn);
end;

procedure TRho3DPlot.MenuProperties(Sender: TObject);
begin
  ShowEditor;
end;

procedure TRho3DPlot.MenuResetView(Sender: TObject);
begin
  ResetView;
end;

procedure TRho3DPlot.ShowEditor;
begin
  if FEditor = nil then
    FEditor := TRho3DPlotEditor.CreateFor(Self);
  TRho3DPlotEditor(FEditor).LoadFromPlot;
  TRho3DPlotEditor(FEditor).Show;
end;

{ ==================================================================== }
{ Property setters                                                      }
{ ==================================================================== }

function TRho3DPlot.GetLimit(Index: Integer): Double;
begin
  Result := FLimits[Index];
end;

procedure TRho3DPlot.SetLimit(Index: Integer; const Value: Double);
begin
  FLimits[Index] := Value;
  SeriesChanged;
end;

function TRho3DPlot.GetAspectRatio(Index: Integer): Single;
begin
  Result := FAspectRatio[Index];
end;

procedure TRho3DPlot.SetAspectRatio(Index: Integer; const Value: Single);
begin
  if Value > 0 then
  begin
    FAspectRatio[Index] := Value;
    SeriesChanged;
  end;
end;

procedure TRho3DPlot.SetAspect(const Value: TRho3DAspect);
begin
  if FAspect <> Value then
  begin
    FAspect := Value;
    SeriesChanged;
  end;
end;

procedure TRho3DPlot.SetColorMin(const Value: Double);
begin
  FColorMin := Value;
  SeriesChanged;
end;

procedure TRho3DPlot.SetColorMax(const Value: Double);
begin
  FColorMax := Value;
  SeriesChanged;
end;

procedure TRho3DPlot.SetTheme(const Value: TRho3DTheme);
begin
  FTheme := Value;
  case Value of
    thLight:
      begin
        FBackgroundColor := DefaultBackgroundColor;
        FCubeColor := DefaultCubeColor;
        FAxisColor := DefaultAxisColor;
        FTextColor := DefaultTextColor;
        FGridColor := DefaultGridColor;
        FPaneColor := DefaultPaneColor;
      end;
    thDark:
      begin
        FBackgroundColor := DarkBackgroundColor;
        FCubeColor := DarkCubeColor;
        FAxisColor := DarkAxisColor;
        FTextColor := DarkTextColor;
        FGridColor := DarkGridColor;
        FPaneColor := DarkPaneColor;
      end;
  end;
  SeriesChanged;   // depth-cue colours use the background
end;

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

procedure TRho3DPlot.SetShowGrid(const Value: Boolean);
begin
  if FShowGrid <> Value then begin FShowGrid := Value; Redraw; end;
end;

procedure TRho3DPlot.SetTickCount(const Value: Integer);
begin
  if (FTickCount <> Value) and (Value >= 1) then
  begin
    FTickCount := Value;
    Redraw;
  end;
end;

procedure TRho3DPlot.SetTickLabels(AAxis: Integer; const APositions: array of Double;
  const ALabels: array of string);
var
  k: Integer;
begin
  if (AAxis < 0) or (AAxis > 2) then
    raise EArgumentException.Create('SetTickLabels: the axis is 0, 1 or 2');
  if Length(APositions) <> Length(ALabels) then
    raise EArgumentException.Create('SetTickLabels: one label per position');
  SetLength(FTickPos[AAxis], Length(APositions));
  SetLength(FTickNames[AAxis], Length(ALabels));
  for k := 0 to High(APositions) do
  begin
    FTickPos[AAxis][k] := APositions[k];
    FTickNames[AAxis][k] := ALabels[k];
  end;
  Redraw;
end;

function TRho3DPlot.HasTickLabels(AAxis: Integer): Boolean;
begin
  Result := (AAxis >= 0) and (AAxis <= 2) and (Length(FTickPos[AAxis]) > 0);
end;

// The ticks of axis A for this render: round numbers, or the named ticks
// inside the axis range (FTickText their labels, FTickStep their smallest
// gap, which the label thinning uses).
procedure TRho3DPlot.ComputeTicks(A: Integer);
var
  k, n: Integer;
  lo, hi, tol, gap: Double;
  sorted: TArray<Double>;
begin
  if Length(FTickPos[A]) = 0 then
  begin
    FTicks[A] := NiceTicks(FFrame.Lo[A], FFrame.Hi[A], FTickCount, FTickStep[A]);
    FTickText[A] := nil;
    Exit;
  end;
  lo := FFrame.Lo[A];
  hi := FFrame.Hi[A];
  tol := (hi - lo) * 1E-9;
  SetLength(FTicks[A], Length(FTickPos[A]));
  SetLength(FTickText[A], Length(FTickPos[A]));
  n := 0;
  for k := 0 to High(FTickPos[A]) do
    if (FTickPos[A][k] >= lo - tol) and (FTickPos[A][k] <= hi + tol) then
    begin
      FTicks[A][n] := FTickPos[A][k];
      FTickText[A][n] := FTickNames[A][k];
      Inc(n);
    end;
  SetLength(FTicks[A], n);
  SetLength(FTickText[A], n);
  sorted := Copy(FTicks[A]);
  TArray.Sort<Double>(sorted);
  FTickStep[A] := 0;
  for k := 1 to High(sorted) do
  begin
    gap := sorted[k] - sorted[k - 1];
    if (gap > 0) and ((FTickStep[A] = 0) or (gap < FTickStep[A])) then
      FTickStep[A] := gap;
  end;
  if FTickStep[A] = 0 then
    FTickStep[A] := hi - lo;
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

procedure TRho3DPlot.SetGridColor(const Value: TAlphaColor);
begin
  if FGridColor <> Value then begin FGridColor := Value; Redraw; end;
end;

procedure TRho3DPlot.SetPaneColor(const Value: TAlphaColor);
begin
  if FPaneColor <> Value then begin FPaneColor := Value; Redraw; end;
end;

function TRho3DPlot.GetAxisTitle(Index: Integer): string;
begin
  case Index of
    0: Result := FAxisTitleX;
    1: Result := FAxisTitleY;
  else
    Result := FAxisTitleZ;
  end;
end;

procedure TRho3DPlot.SetAxisTitle(Index: Integer; const Value: string);
begin
  case Index of
    0: FAxisTitleX := Value;
    1: FAxisTitleY := Value;
  else
    FAxisTitleZ := Value;
  end;
  Redraw;
end;

procedure TRho3DPlot.SetChartTitle(const Value: string);
begin
  if FChartTitle <> Value then begin FChartTitle := Value; Redraw; end;
end;

function TRho3DPlot.GetFontSize(Index: Integer): Single;
begin
  case Index of
    0: Result := FTickFontSize;
    1..3: Result := FAxisTitleFontSize[Index - 1];
  else
    Result := FChartTitleFontSize;
  end;
end;

procedure TRho3DPlot.SetFontSize(Index: Integer; const Value: Single);
begin
  if not (Value > 0) or (Value = GetFontSize(Index)) then
    Exit;
  case Index of
    0: FTickFontSize := Value;
    1..3: FAxisTitleFontSize[Index - 1] := Value;
  else
    FChartTitleFontSize := Value;
  end;
  // the fonts are made again, at the new sizes, by the next render
  FFontTick := nil;
  FFontTitle[0] := nil;
  FFontTitle[1] := nil;
  FFontTitle[2] := nil;
  FFontChart := nil;
  Redraw;
end;

procedure TRho3DPlot.SetShowColorBar(const Value: Boolean);
begin
  if FShowColorBar <> Value then begin FShowColorBar := Value; Redraw; end;
end;

procedure TRho3DPlot.SetColorBarTitle(const Value: string);
begin
  if FColorBarTitle <> Value then begin FColorBarTitle := Value; Redraw; end;
end;

procedure TRho3DPlot.SetLightAzimuth(const Value: Single);
begin
  FLightAzimuth := Value;
  Redraw;
end;

procedure TRho3DPlot.SetLightElevation(const Value: Single);
begin
  FLightElevation := EnsureRange(Value, -90, 90);
  Redraw;
end;

procedure TRho3DPlot.SetAmbient(const Value: Single);
begin
  FAmbient := EnsureRange(Value, 0, 1);
  Redraw;
end;

procedure TRho3DPlot.SetLegendVisible(const Value: Boolean);
begin
  if FLegendVisible <> Value then begin FLegendVisible := Value; Redraw; end;
end;

procedure TRho3DPlot.SetLegendLocation(const Value: TRho3DLegendLocation);
begin
  FLegendLocation := Value;
  FLegendOffset := TPointF.Zero;   // a new corner forgets any drag
  Redraw;
end;

procedure TRho3DPlot.SetLineColor(const Value: TAlphaColor);
var
  s: TRho3DSeries;
begin
  FLineColor := Value;
  for s in FSeries do
    s.FColor := Value;
  SeriesChanged;
end;

procedure TRho3DPlot.SetLineThickness(const Value: Single);
var
  s: TRho3DSeries;
begin
  FLineThickness := Value;
  for s in FSeries do
    s.FThickness := Value;
  SeriesChanged;
end;

procedure TRho3DPlot.SetUseGradient(const Value: Boolean);
var
  s: TRho3DSeries;
begin
  FUseGradient := Value;
  for s in FSeries do
    s.FUseGradient := Value;
  SeriesChanged;
end;

procedure TRho3DPlot.SetGradientStartColor(const Value: TAlphaColor);
var
  s: TRho3DSeries;
begin
  FGradientStartColor := Value;
  for s in FSeries do
    s.FGradientStartColor := Value;
  SeriesChanged;
end;

procedure TRho3DPlot.SetGradientEndColor(const Value: TAlphaColor);
var
  s: TRho3DSeries;
begin
  FGradientEndColor := Value;
  for s in FSeries do
    s.FGradientEndColor := Value;
  SeriesChanged;
end;

procedure TRho3DPlot.SetShowLines(const Value: Boolean);
var
  s: TRho3DSeries;
begin
  FShowLines := Value;
  for s in FSeries do
    s.FShowLine := Value;
  SeriesChanged;
end;

procedure TRho3DPlot.SetShowPoints(const Value: Boolean);
var
  s: TRho3DSeries;
begin
  FShowPoints := Value;
  for s in FSeries do
    s.FShowPoints := Value;
  SeriesChanged;
end;

procedure TRho3DPlot.SetPointSize(const Value: Single);
var
  s: TRho3DSeries;
begin
  FPointSize := Value;
  for s in FSeries do
    s.FPointSize := Value;
  SeriesChanged;
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
    FRotateWatch := TStopwatch.StartNew;
    FRotateTimer.Enabled := Value;
    if not Value then
      Redraw;   // back to full detail
  end;
end;

procedure TRho3DPlot.SetAutoRotateSpeed(const Value: Single);
begin
  FAutoRotateSpeed := Value;
end;

procedure TRho3DPlot.SetRevealFraction(const Value: Single);
begin
  FRevealFraction := EnsureRange(Value, 0, 1);
  Redraw;
end;

procedure TRho3DPlot.SetReducedDetail(const Value: Boolean);
begin
  if FInteracting <> Value then
  begin
    FInteracting := Value;
    Redraw;
  end;
end;

procedure TRho3DPlot.SetShowRevealHead(const Value: Boolean);
begin
  if FShowRevealHead <> Value then begin FShowRevealHead := Value; Redraw; end;
end;

end.
