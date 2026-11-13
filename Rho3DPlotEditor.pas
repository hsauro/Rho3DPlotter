unit Rho3DPlotEditor;

{
  Run-time property editor for TRho3DPlot, opened by double-clicking the plot
  (or TRho3DPlot.ShowEditor). Tabs: General, Axes, Series, Lighting, Legend.
  Every change is applied to the plot immediately.

  The form is built in code (no .fmx) and uses only standard FMX controls, so
  the component needs no extra packages and stays independent of the 2D
  component's editor.
}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.UITypes,
  System.Math,
  FMX.Types,
  FMX.Controls,
  FMX.Forms,
  FMX.StdCtrls,
  FMX.Edit,
  FMX.ListBox,
  FMX.TabControl,
  FMX.Layouts,
  FMX.Colors,
  FMX.Controls.Presentation,
  Rho3DPlot;

type
  TRho3DPlotEditor = class(TForm)
  private
    FPlot: TRho3DPlot;
    FLoading: Boolean;
    FTabs: TTabControl;
    // General
    edtTitle: TEdit;
    cmbTheme: TComboBox;
    colBackground: TComboColorBox;
    cmbProjection: TComboBox;
    cmbAspect: TComboBox;
    edtAspX, edtAspY, edtAspZ: TEdit;
    chkColorBar: TCheckBox;
    edtColorBarTitle: TEdit;
    edtCMin, edtCMax: TEdit;
    chkHover: TCheckBox;
    chkDepthCue: TCheckBox;
    // Axes
    edtAxTitle: array[0..2] of TEdit;
    edtLimit: array[0..5] of TEdit;
    edtTickCount: TEdit;
    chkBox, chkAxes, chkTicks, chkValues, chkGrid: TCheckBox;
    colBox, colAxis, colText, colGrid, colPane: TComboColorBox;
    // Series
    cmbSeries: TComboBox;
    edtSTitle: TEdit;
    chkSVisible, chkSLegend, chkSLine, chkSPoints, chkSGradient: TCheckBox;
    colSColor, colSGradStart, colSGradEnd: TComboColorBox;
    edtSThickness, edtSPointSize: TEdit;
    cmbSMarker: TComboBox;
    trkSOpacity: TTrackBar;
    chkSColorByValue: TCheckBox;
    cmbSColorMap: TComboBox;
    cmbSFill: TComboBox;
    colSEdge: TComboColorBox;
    edtSEdgeWidth: TEdit;
    chkSShaded: TCheckBox;
    // Lighting
    trkLightAz, trkLightEl, trkAmbient: TTrackBar;
    // Legend
    chkLegend: TCheckBox;
    cmbLegendLoc: TComboBox;

    function NewPage(const ACaption: string): TVertScrollBox;
    function Row(AParent: TFmxObject; const ACaption: string): TLayout;
    function AddEdit(AParent: TFmxObject; const ACaption: string): TEdit;
    function AddCheck(AParent: TFmxObject; const ACaption: string): TCheckBox;
    function AddCombo(AParent: TFmxObject; const ACaption: string;
      const AItems: array of string): TComboBox;
    function AddColor(AParent: TFmxObject; const ACaption: string): TComboColorBox;
    function AddTrack(AParent: TFmxObject; const ACaption: string;
      AMin, AMax: Single): TTrackBar;
    procedure AddHeading(AParent: TFmxObject; const ACaption: string);
    procedure AddButtons(AParent: TFmxObject; const ACaptions: array of string;
      AHandler: TNotifyEvent);
    procedure BuildUI;
    function SelectedSeries: TRho3DSeries;
    procedure LoadSeries;
    procedure Changed(Sender: TObject);
    procedure ThemeChanged(Sender: TObject);
    procedure SeriesSelected(Sender: TObject);
    procedure SeriesChanged(Sender: TObject);
    procedure ViewButton(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  public
    constructor CreateFor(APlot: TRho3DPlot);
    /// Copy the plot's current state into the controls.
    procedure LoadFromPlot;
  end;

implementation

uses
  Rho3DColorMaps,
  Rho3DTransform;

function NumText(const V: Double): string;
begin
  if IsNan(V) then
    Result := ''
  else
    Result := FloatToStrF(V, ffGeneral, 8, 0);
end;

/// Empty text -> NaN (automatic); unparsable text -> ADefault.
function TextNum(const S: string; const ADefault: Double): Double;
var
  t: string;
  fs: TFormatSettings;
begin
  t := S.Trim;
  if t = '' then
    Exit(NaN);
  if TryStrToFloat(t, Result) then
    Exit;
  fs := TFormatSettings.Invariant;
  if not TryStrToFloat(t, Result, fs) then
    Result := ADefault;
end;

{ TRho3DPlotEditor }

constructor TRho3DPlotEditor.CreateFor(APlot: TRho3DPlot);
begin
  inherited CreateNew(nil);
  FPlot := APlot;
  Caption := '3D Plot Properties';
  Width := 440;
  Height := 600;
  Position := TFormPosition.ScreenCenter;
  OnClose := FormClose;
  BuildUI;
end;

procedure TRho3DPlotEditor.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := TCloseAction.caHide;
end;

function TRho3DPlotEditor.NewPage(const ACaption: string): TVertScrollBox;
var
  tab: TTabItem;
begin
  tab := FTabs.Add;
  tab.Text := ACaption;
  Result := TVertScrollBox.Create(Self);
  Result.Parent := tab;
  Result.Align := TAlignLayout.Client;
  Result.Padding.Rect := TRectF.Create(4, 6, 4, 6);
end;

function TRho3DPlotEditor.Row(AParent: TFmxObject; const ACaption: string): TLayout;
var
  lbl: TLabel;
begin
  Result := TLayout.Create(Self);
  Result.Parent := AParent;
  Result.Position.Y := 1E6;          // stack below the existing rows
  Result.Align := TAlignLayout.Top;
  Result.Height := 30;
  Result.Margins.Left := 6;
  Result.Margins.Right := 6;
  lbl := TLabel.Create(Self);
  lbl.Parent := Result;
  lbl.Align := TAlignLayout.Left;
  lbl.Width := 140;
  lbl.Text := ACaption;
end;

function TRho3DPlotEditor.AddEdit(AParent: TFmxObject; const ACaption: string): TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Parent := Row(AParent, ACaption);
  Result.Align := TAlignLayout.Client;
  Result.Margins.Top := 3;
  Result.Margins.Bottom := 3;
  Result.OnChange := Changed;
end;

function TRho3DPlotEditor.AddCheck(AParent: TFmxObject; const ACaption: string): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := Row(AParent, '');
  Result.Align := TAlignLayout.Client;
  Result.Text := ACaption;
  Result.OnChange := Changed;
end;

function TRho3DPlotEditor.AddCombo(AParent: TFmxObject; const ACaption: string;
  const AItems: array of string): TComboBox;
var
  i: Integer;
begin
  Result := TComboBox.Create(Self);
  Result.Parent := Row(AParent, ACaption);
  Result.Align := TAlignLayout.Client;
  Result.Margins.Top := 3;
  Result.Margins.Bottom := 3;
  for i := 0 to High(AItems) do
    Result.Items.Add(AItems[i]);
  Result.OnChange := Changed;
end;

function TRho3DPlotEditor.AddColor(AParent: TFmxObject; const ACaption: string): TComboColorBox;
begin
  Result := TComboColorBox.Create(Self);
  Result.Parent := Row(AParent, ACaption);
  Result.Align := TAlignLayout.Client;
  Result.Margins.Top := 3;
  Result.Margins.Bottom := 3;
  Result.OnChange := Changed;
end;

function TRho3DPlotEditor.AddTrack(AParent: TFmxObject; const ACaption: string;
  AMin, AMax: Single): TTrackBar;
begin
  Result := TTrackBar.Create(Self);
  Result.Parent := Row(AParent, ACaption);
  Result.Align := TAlignLayout.Client;
  Result.Margins.Top := 6;
  Result.Min := AMin;
  Result.Max := AMax;
  Result.OnChange := Changed;
end;

procedure TRho3DPlotEditor.AddHeading(AParent: TFmxObject; const ACaption: string);
var
  r: TLayout;
begin
  r := Row(AParent, ACaption);
  r.Height := 26;
  // Bold, but colour, family and size from the style, so headings follow
  // light and dark themes.
  TLabel(r.Children[0]).StyledSettings :=
    TLabel(r.Children[0]).StyledSettings - [TStyledSetting.Style];
  TLabel(r.Children[0]).TextSettings.Font.Style := [TFontStyle.fsBold];
  TLabel(r.Children[0]).Width := 300;
end;

procedure TRho3DPlotEditor.AddButtons(AParent: TFmxObject;
  const ACaptions: array of string; AHandler: TNotifyEvent);
var
  r: TLayout;
  i: Integer;
  b: TButton;
begin
  r := Row(AParent, '');
  r.Children[0].Free;   // no caption
  for i := 0 to High(ACaptions) do
  begin
    b := TButton.Create(Self);
    b.Parent := r;
    b.Position.X := 1E5;
    b.Align := TAlignLayout.Left;
    b.Width := 76;
    b.Margins.Right := 4;
    b.Text := ACaptions[i];
    b.Tag := i;
    b.OnClick := AHandler;
  end;
end;

procedure TRho3DPlotEditor.BuildUI;
var
  pg: TVertScrollBox;
  m: TRho3DColorMap;
  maps: TArray<string>;
  i: Integer;
const
  LimitNames: array[0..5] of string =
    ('X min', 'X max', 'Y min', 'Y max', 'Z min', 'Z max');
  AxisNames: array[0..2] of string = ('X title', 'Y title', 'Z title');
begin
  FTabs := TTabControl.Create(Self);
  FTabs.Parent := Self;
  FTabs.Align := TAlignLayout.Client;

  // ---- General ----
  pg := NewPage('General');
  edtTitle := AddEdit(pg, 'Chart title');
  cmbTheme := AddCombo(pg, 'Theme', ['Light', 'Dark']);
  cmbTheme.OnChange := ThemeChanged;
  colBackground := AddColor(pg, 'Background');
  cmbProjection := AddCombo(pg, 'Projection', ['Perspective', 'Orthographic']);
  cmbAspect := AddCombo(pg, 'Aspect', ['Independent (fill box)', 'Equal', 'Custom ratios']);
  edtAspX := AddEdit(pg, 'Custom ratio X');
  edtAspY := AddEdit(pg, 'Custom ratio Y');
  edtAspZ := AddEdit(pg, 'Custom ratio Z');
  AddHeading(pg, 'View');
  AddButtons(pg, ['Isometric', 'Top', 'Front', 'Side', 'Reset'], ViewButton);
  AddHeading(pg, 'Colour bar');
  chkColorBar := AddCheck(pg, 'Show colour bar');
  edtColorBarTitle := AddEdit(pg, 'Colour bar title');
  edtCMin := AddEdit(pg, 'Colour min (blank=auto)');
  edtCMax := AddEdit(pg, 'Colour max (blank=auto)');
  AddHeading(pg, 'Other');
  chkHover := AddCheck(pg, 'Hover read-out');
  chkDepthCue := AddCheck(pg, 'Depth-cue markers');

  // ---- Axes ----
  pg := NewPage('Axes');
  for i := 0 to 2 do
    edtAxTitle[i] := AddEdit(pg, AxisNames[i]);
  AddHeading(pg, 'Limits (blank = automatic)');
  for i := 0 to 5 do
    edtLimit[i] := AddEdit(pg, LimitNames[i]);
  AddHeading(pg, 'Box and ticks');
  edtTickCount := AddEdit(pg, 'Tick count (approx.)');
  chkBox := AddCheck(pg, 'Show box');
  chkAxes := AddCheck(pg, 'Show axes');
  chkTicks := AddCheck(pg, 'Show ticks');
  chkValues := AddCheck(pg, 'Show tick values');
  chkGrid := AddCheck(pg, 'Grid on back planes');
  colBox := AddColor(pg, 'Box colour');
  colAxis := AddColor(pg, 'Axis colour');
  colText := AddColor(pg, 'Text colour');
  colGrid := AddColor(pg, 'Grid colour');
  colPane := AddColor(pg, 'Back-plane fill');

  // ---- Series ----
  pg := NewPage('Series');
  cmbSeries := AddCombo(pg, 'Series', []);
  cmbSeries.OnChange := SeriesSelected;
  edtSTitle := AddEdit(pg, 'Title');
  chkSVisible := AddCheck(pg, 'Visible');
  chkSLegend := AddCheck(pg, 'Show in legend');
  colSColor := AddColor(pg, 'Colour');
  trkSOpacity := AddTrack(pg, 'Opacity', 0, 1);
  chkSColorByValue := AddCheck(pg, 'Colour by value (colour map)');
  SetLength(maps, 0);
  for m := Low(TRho3DColorMap) to High(TRho3DColorMap) do
    maps := maps + [ColorMapNames[m]];
  cmbSColorMap := AddCombo(pg, 'Colour map', maps);
  AddHeading(pg, 'Curve / scatter');
  chkSLine := AddCheck(pg, 'Show line');
  edtSThickness := AddEdit(pg, 'Line width');
  chkSGradient := AddCheck(pg, 'Gradient along curve');
  colSGradStart := AddColor(pg, 'Gradient start');
  colSGradEnd := AddColor(pg, 'Gradient end');
  chkSPoints := AddCheck(pg, 'Show markers');
  cmbSMarker := AddCombo(pg, 'Marker', ['Circle', 'Square', 'Diamond', 'Triangle', 'Cross']);
  edtSPointSize := AddEdit(pg, 'Marker size');
  AddHeading(pg, 'Surface and bars');
  cmbSFill := AddCombo(pg, 'Fill mode', ['Filled', 'Wireframe', 'Filled with edges']);
  colSEdge := AddColor(pg, 'Edge colour');
  edtSEdgeWidth := AddEdit(pg, 'Edge width');
  chkSShaded := AddCheck(pg, 'Shaded (Lambert)');
  // series controls apply to the selected series only
  edtSTitle.OnChange := SeriesChanged;
  chkSVisible.OnChange := SeriesChanged;
  chkSLegend.OnChange := SeriesChanged;
  colSColor.OnChange := SeriesChanged;
  trkSOpacity.OnChange := SeriesChanged;
  chkSColorByValue.OnChange := SeriesChanged;
  cmbSColorMap.OnChange := SeriesChanged;
  chkSLine.OnChange := SeriesChanged;
  edtSThickness.OnChange := SeriesChanged;
  chkSGradient.OnChange := SeriesChanged;
  colSGradStart.OnChange := SeriesChanged;
  colSGradEnd.OnChange := SeriesChanged;
  chkSPoints.OnChange := SeriesChanged;
  cmbSMarker.OnChange := SeriesChanged;
  edtSPointSize.OnChange := SeriesChanged;
  cmbSFill.OnChange := SeriesChanged;
  colSEdge.OnChange := SeriesChanged;
  edtSEdgeWidth.OnChange := SeriesChanged;
  chkSShaded.OnChange := SeriesChanged;

  // ---- Lighting ----
  pg := NewPage('Lighting');
  trkLightAz := AddTrack(pg, 'Light azimuth', -180, 180);
  trkLightEl := AddTrack(pg, 'Light elevation', -90, 90);
  trkAmbient := AddTrack(pg, 'Ambient', 0, 1);
  AddHeading(pg, 'Lighting applies to series with "Shaded" on.');

  // ---- Legend ----
  pg := NewPage('Legend');
  chkLegend := AddCheck(pg, 'Show legend');
  cmbLegendLoc := AddCombo(pg, 'Location', ['Top right', 'Top left', 'Bottom right', 'Bottom left']);
  AddHeading(pg, 'Drag the legend to move it; click an entry to hide / show.');

  FTabs.TabIndex := 0;
end;

function TRho3DPlotEditor.SelectedSeries: TRho3DSeries;
begin
  if (cmbSeries.ItemIndex >= 0) and (cmbSeries.ItemIndex < FPlot.SeriesCount) then
    Result := FPlot.Series[cmbSeries.ItemIndex]
  else
    Result := nil;
end;

procedure TRho3DPlotEditor.LoadFromPlot;
var
  i, sel: Integer;
  s: TRho3DSeries;
  lim: array[0..5] of Double;
begin
  FLoading := True;
  try
    edtTitle.Text := FPlot.ChartTitle;
    cmbTheme.ItemIndex := Ord(FPlot.Theme);
    colBackground.Color := FPlot.BackgroundColor;
    cmbProjection.ItemIndex := Ord(FPlot.Projection);
    cmbAspect.ItemIndex := Ord(FPlot.Aspect);
    edtAspX.Text := NumText(FPlot.AspectX);
    edtAspY.Text := NumText(FPlot.AspectY);
    edtAspZ.Text := NumText(FPlot.AspectZ);
    chkColorBar.IsChecked := FPlot.ShowColorBar;
    edtColorBarTitle.Text := FPlot.ColorBarTitle;
    edtCMin.Text := NumText(FPlot.ColorMin);
    edtCMax.Text := NumText(FPlot.ColorMax);
    chkHover.IsChecked := FPlot.ShowHoverInfo;
    chkDepthCue.IsChecked := FPlot.DepthCue;

    edtAxTitle[0].Text := FPlot.AxisTitleX;
    edtAxTitle[1].Text := FPlot.AxisTitleY;
    edtAxTitle[2].Text := FPlot.AxisTitleZ;
    lim[0] := FPlot.XMin; lim[1] := FPlot.XMax;
    lim[2] := FPlot.YMin; lim[3] := FPlot.YMax;
    lim[4] := FPlot.ZMin; lim[5] := FPlot.ZMax;
    for i := 0 to 5 do
      edtLimit[i].Text := NumText(lim[i]);
    edtTickCount.Text := IntToStr(FPlot.TickCount);
    chkBox.IsChecked := FPlot.ShowCube;
    chkAxes.IsChecked := FPlot.ShowAxes;
    chkTicks.IsChecked := FPlot.ShowTicks;
    chkValues.IsChecked := FPlot.ShowValues;
    chkGrid.IsChecked := FPlot.ShowGrid;
    colBox.Color := FPlot.CubeColor;
    colAxis.Color := FPlot.AxisColor;
    colText.Color := FPlot.TextColor;
    colGrid.Color := FPlot.GridColor;
    colPane.Color := FPlot.PaneColor;

    trkLightAz.Value := FPlot.LightAzimuth;
    trkLightEl.Value := FPlot.LightElevation;
    trkAmbient.Value := FPlot.Ambient;

    chkLegend.IsChecked := FPlot.LegendVisible;
    cmbLegendLoc.ItemIndex := Ord(FPlot.LegendLocation);

    sel := Max(cmbSeries.ItemIndex, 0);
    cmbSeries.Items.BeginUpdate;
    try
      cmbSeries.Items.Clear;
      for i := 0 to FPlot.SeriesCount - 1 do
      begin
        s := FPlot.Series[i];
        cmbSeries.Items.Add(Format('%d: %s (%s)', [i + 1, s.Title, SeriesKindNames[s.Kind]]));
      end;
    finally
      cmbSeries.Items.EndUpdate;
    end;
    if FPlot.SeriesCount > 0 then
      cmbSeries.ItemIndex := Min(sel, FPlot.SeriesCount - 1);
  finally
    FLoading := False;
  end;
  LoadSeries;
end;

procedure TRho3DPlotEditor.LoadSeries;
var
  s: TRho3DSeries;
begin
  s := SelectedSeries;
  FLoading := True;
  try
    if s = nil then
      Exit;
    edtSTitle.Text := s.Title;
    chkSVisible.IsChecked := s.Visible;
    chkSLegend.IsChecked := s.ShowInLegend;
    colSColor.Color := s.Color;
    trkSOpacity.Value := s.Opacity;
    chkSColorByValue.IsChecked := s.ColorByValue;
    cmbSColorMap.ItemIndex := Ord(s.ColorMap);
    chkSLine.IsChecked := s.ShowLine;
    edtSThickness.Text := NumText(s.Thickness);
    chkSGradient.IsChecked := s.UseGradient;
    colSGradStart.Color := s.GradientStartColor;
    colSGradEnd.Color := s.GradientEndColor;
    chkSPoints.IsChecked := s.ShowPoints;
    cmbSMarker.ItemIndex := Ord(s.MarkerShape);
    edtSPointSize.Text := NumText(s.PointSize);
    cmbSFill.ItemIndex := Ord(s.FillMode);
    colSEdge.Color := s.EdgeColor;
    edtSEdgeWidth.Text := NumText(s.EdgeWidth);
    chkSShaded.IsChecked := s.Shaded;
  finally
    FLoading := False;
  end;
end;

procedure TRho3DPlotEditor.ThemeChanged(Sender: TObject);
begin
  if FLoading or (cmbTheme.ItemIndex < 0) then
    Exit;
  FPlot.Theme := TRho3DTheme(cmbTheme.ItemIndex);
  LoadFromPlot;   // the theme resets the colours shown on the other controls
end;

procedure TRho3DPlotEditor.ViewButton(Sender: TObject);
begin
  case TComponent(Sender).Tag of
    0: FPlot.ViewPreset(vpIsometric);
    1: FPlot.ViewPreset(vpTop);
    2: FPlot.ViewPreset(vpFront);
    3: FPlot.ViewPreset(vpSide);
  else
    FPlot.ResetView;
  end;
end;

procedure TRho3DPlotEditor.SeriesSelected(Sender: TObject);
begin
  if not FLoading then
    LoadSeries;
end;

procedure TRho3DPlotEditor.Changed(Sender: TObject);
var
  v: Double;
  i: Integer;
  lim: Double;
begin
  if FLoading then
    Exit;
  FPlot.ChartTitle := edtTitle.Text;
  FPlot.BackgroundColor := colBackground.Color;
  if cmbProjection.ItemIndex >= 0 then
    FPlot.Projection := TRho3DProjection(cmbProjection.ItemIndex);
  v := TextNum(edtAspX.Text, FPlot.AspectX);
  if v > 0 then FPlot.AspectX := v;
  v := TextNum(edtAspY.Text, FPlot.AspectY);
  if v > 0 then FPlot.AspectY := v;
  v := TextNum(edtAspZ.Text, FPlot.AspectZ);
  if v > 0 then FPlot.AspectZ := v;
  if cmbAspect.ItemIndex >= 0 then
    FPlot.Aspect := TRho3DAspect(cmbAspect.ItemIndex);
  FPlot.ShowColorBar := chkColorBar.IsChecked;
  FPlot.ColorBarTitle := edtColorBarTitle.Text;
  FPlot.ColorMin := TextNum(edtCMin.Text, FPlot.ColorMin);
  FPlot.ColorMax := TextNum(edtCMax.Text, FPlot.ColorMax);
  FPlot.ShowHoverInfo := chkHover.IsChecked;
  FPlot.DepthCue := chkDepthCue.IsChecked;

  FPlot.AxisTitleX := edtAxTitle[0].Text;
  FPlot.AxisTitleY := edtAxTitle[1].Text;
  FPlot.AxisTitleZ := edtAxTitle[2].Text;
  for i := 0 to 5 do
  begin
    case i of
      0: lim := FPlot.XMin;
      1: lim := FPlot.XMax;
      2: lim := FPlot.YMin;
      3: lim := FPlot.YMax;
      4: lim := FPlot.ZMin;
    else
      lim := FPlot.ZMax;
    end;
    v := TextNum(edtLimit[i].Text, lim);
    // only touch a limit that changed (each one re-prepares the plot)
    if not ((IsNan(v) and IsNan(lim)) or (v = lim)) then
      case i of
        0: FPlot.XMin := v;
        1: FPlot.XMax := v;
        2: FPlot.YMin := v;
        3: FPlot.YMax := v;
        4: FPlot.ZMin := v;
      else
        FPlot.ZMax := v;
      end;
  end;
  v := TextNum(edtTickCount.Text, FPlot.TickCount);
  if not IsNan(v) and (v >= 1) then
    FPlot.TickCount := Round(v);
  FPlot.ShowCube := chkBox.IsChecked;
  FPlot.ShowAxes := chkAxes.IsChecked;
  FPlot.ShowTicks := chkTicks.IsChecked;
  FPlot.ShowValues := chkValues.IsChecked;
  FPlot.ShowGrid := chkGrid.IsChecked;
  FPlot.CubeColor := colBox.Color;
  FPlot.AxisColor := colAxis.Color;
  FPlot.TextColor := colText.Color;
  FPlot.GridColor := colGrid.Color;
  FPlot.PaneColor := colPane.Color;

  FPlot.LightAzimuth := trkLightAz.Value;
  FPlot.LightElevation := trkLightEl.Value;
  FPlot.Ambient := trkAmbient.Value;

  FPlot.LegendVisible := chkLegend.IsChecked;
  if (cmbLegendLoc.ItemIndex >= 0) and
     (TRho3DLegendLocation(cmbLegendLoc.ItemIndex) <> FPlot.LegendLocation) then
    FPlot.LegendLocation := TRho3DLegendLocation(cmbLegendLoc.ItemIndex);
end;

procedure TRho3DPlotEditor.SeriesChanged(Sender: TObject);
var
  s: TRho3DSeries;
  v: Double;
  idx: Integer;
begin
  if FLoading then
    Exit;
  s := SelectedSeries;
  if s = nil then
    Exit;
  s.Title := edtSTitle.Text;
  s.Visible := chkSVisible.IsChecked;
  s.ShowInLegend := chkSLegend.IsChecked;
  s.Color := colSColor.Color;
  s.Opacity := trkSOpacity.Value;
  s.ColorByValue := chkSColorByValue.IsChecked;
  if cmbSColorMap.ItemIndex >= 0 then
    s.ColorMap := TRho3DColorMap(cmbSColorMap.ItemIndex);
  s.ShowLine := chkSLine.IsChecked;
  v := TextNum(edtSThickness.Text, s.Thickness);
  if not IsNan(v) and (v > 0) then s.Thickness := v;
  s.UseGradient := chkSGradient.IsChecked;
  s.GradientStartColor := colSGradStart.Color;
  s.GradientEndColor := colSGradEnd.Color;
  s.ShowPoints := chkSPoints.IsChecked;
  if cmbSMarker.ItemIndex >= 0 then
    s.MarkerShape := TRho3DMarker(cmbSMarker.ItemIndex);
  v := TextNum(edtSPointSize.Text, s.PointSize);
  if not IsNan(v) and (v > 0) then s.PointSize := v;
  if cmbSFill.ItemIndex >= 0 then
    s.FillMode := TRho3DFillMode(cmbSFill.ItemIndex);
  s.EdgeColor := colSEdge.Color;
  v := TextNum(edtSEdgeWidth.Text, s.EdgeWidth);
  if not IsNan(v) and (v >= 0) then s.EdgeWidth := v;
  s.Shaded := chkSShaded.IsChecked;
  // keep the series list caption in step with the title
  idx := cmbSeries.ItemIndex;
  if (Sender = edtSTitle) and (idx >= 0) then
  begin
    FLoading := True;
    try
      cmbSeries.Items[idx] := Format('%d: %s (%s)', [idx + 1, s.Title, SeriesKindNames[s.Kind]]);
      cmbSeries.ItemIndex := idx;
    finally
      FLoading := False;
    end;
  end;
end;

end.
