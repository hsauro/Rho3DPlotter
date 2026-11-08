# TRho3DPlot — a Skia-backed 3D plotting component for Delphi FireMonkey

An interactive 3D plotting control for RAD Studio **FireMonkey (FMX)**, rendered
with the **Skia** backend. `TRho3DPlot` draws parametric curves (Lorenz, Rössler
and Chua attractors), 3D scatter clouds, surfaces `z = f(x, y)` and parametric
surfaces (tori, spheres, Möbius strips) in one depth-sorted scene that the user
can rotate, zoom and pan, with axes, round-number ticks, a colour bar, a legend,
a property editor, PNG / PDF export and JSON save / load.

It is the 3D companion to the 2D chart `TSkPlotPaintBox`
([Plot2DComponent](https://github.com/hsauro/Plot2DComponent)); the two share no
code, so either can be used without the other.

This code was developed using a combination of human effort and AI assistance.

---

## Contents

- [Installing](#installing)
- [Building](#building)
- [Quick start](#quick-start)
- [Series](#series)
- [Colour](#colour)
- [Axes, box and themes](#axes-box-and-themes)
- [View and interaction](#view-and-interaction)
- [Legend](#legend)
- [Animation and streaming](#animation-and-streaming)
- [Export and persistence](#export-and-persistence)
- [Performance](#performance)
- [Testing](#testing)
- [Units](#units)

## Installing

1. Skia must be available (it ships with RAD Studio 12+ as `Skia.Package.RTL`
   and `Skia.Package.FMX`).
2. Build and install **`Package/Rho3DPlotDesign.dproj`** — it registers
   `TRho3DPlot` on the **Rhody Controls** palette page. The run-time package
   `Package/Rho3DPlotRuntime.dproj` must be built first (the group
   `Package/Rho3DPlotGroup.groupproj` builds them in order).
3. Or skip the packages and add the units to your project (see [Units](#units)).

Set `GlobalUseSkia := True` before `Application.Initialize` (recommended; see
`Plotter3DProject.dpr`).

## Building

| Project | Purpose |
| --- | --- |
| `Package/Rho3DPlotGroup.groupproj` | Everything, in dependency order |
| `Package/Rho3DPlotRuntime.dproj` | `{$RUNONLY}` — all the code |
| `Package/Rho3DPlotDesign.dproj` | `{$DESIGNONLY}` — palette registration |
| `Plotter3DProject.dproj` | Demo application (Win64) |
| `Tests/run_tests.bat` | Unit tests (console) |

Command line (RAD Studio 13 / BDS 37.0):

```cmd
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
msbuild Package\Rho3DPlotGroup.groupproj /t:Build /p:Config=Debug /p:Platform=Win64
```

> Adding a source unit needs **two** edits: `Package/Rho3DPlotRuntime.dpk`
> (`contains`) and `Rho3DPlotRuntime.dproj` (`<DCCReference>`), plus the demo's
> `.dpr` / `.dproj`.

## Quick start

```pascal
uses Rho3DPlot;

Plot := TRho3DPlot.Create(Self);
Plot.Parent := Self;
Plot.Align := TAlignLayout.Client;

// a trajectory, coloured start -> end
Plot.SetPlotData(X, Y, Z);
Plot.Series[0].Title := 'Lorenz';

// a surface z = f(x, y) with a curve on it
S := Plot.AddSurface(GridX, GridY, Zmatrix);    // Z[i][j] at (GridX[j], GridY[i])
S.Opacity := 0.8;
C := Plot.AddCurve(PX, PY, PZ);
C.Thickness := 2.5;
```

## Series

A plot holds any number of `TRho3DSeries`, of any kinds together.

| Kind | Create with | Data |
| --- | --- | --- |
| `skCurve` | `AddCurve(X, Y, Z)`, `AddSeries`, `SetPlotData` | `Points`; a NaN in any coordinate lifts the pen |
| `skScatter` | `AddScatter(X, Y, Z)` | `Points`, optional `SetValues(V)` for colour |
| `skSurface` | `AddSurface(X, Y, Z)` | `X[j]`, `Y[i]`, `Z[i][j]`; NaN in Z leaves a hole |
| `skParametricSurface` | `AddParametricSurface(X, Y, Z)` | matrices `X[i][j]`, `Y[i][j]`, `Z[i][j]` |

Per-series style: `Color`, `Thickness`, `UseGradient` (+ start / end colours),
`ShowLine`, `ShowPoints`, `PointSize`, `MarkerShape` (circle, square, diamond,
triangle, cross), `Opacity` (0..1), `ColorMap`, `ColorByValue`, `FillMode`
(`fmFilled`, `fmWireframe`, `fmFilledWithEdges`), `EdgeColor`, `EdgeWidth`,
`Shaded` (flat Lambert lighting), `Visible`, `ShowInLegend`, `Title`.

After editing `Points` directly, call `Series.Changed`. `PointAt(i)` returns a
point's data coordinates (surfaces: `i = row * Cols + col`); `ValueAt(i)` its
colour value.

The plot-level "master" properties (`LineColor`, `LineThickness`, `UseGradient`,
gradient colours, `ShowLines`, `ShowPoints`, `PointSize`) apply to **every**
series and seed new ones.

## Colour

- Solid `Color`, or a start → end gradient along a curve (`UseGradient`).
- Colour maps (`TRho3DColorMap`): `cmViridis` (default), `cmPlasma`,
  `cmCoolwarm` (diverging), `cmGray`, `cmJet` (compatibility only).
- Surfaces are coloured by height by default; `SetValues(C)` colours them by a
  separate matrix. Scatters (and curves) are coloured by `SetValues(V)`.
- All colour-mapped series share one range: automatic from the data, or fixed
  with `ColorMin` / `ColorMax` (NaN = automatic) so several plots share a scale.
- `ShowColorBar` (default on) draws a colour bar with round-number ticks and an
  optional `ColorBarTitle`.

Lighting (`Shaded` series): `LightAzimuth`, `LightElevation` (degrees, relative
to the viewer) and `Ambient` (0..1).

## Axes, box and themes

- Round-number ticks (1, 2, 5 × 10ⁿ), about `TickCount` intervals per axis,
  placed on the box edges on the outline nearest the viewer (as MATLAB and
  matplotlib do) so they never sit behind the data. An axis seen nearly end-on
  is left unlabelled.
- `AxisTitleX/Y/Z`, `ChartTitle`.
- `Aspect`: `asIndependent` (default; fills the box), `asEqual` (one data unit
  is the same length on every axis), `asCustom` with `AspectX/Y/Z`.
- Fixed limits `XMin` … `ZMax` (NaN = automatic); data outside is clipped.
  `SetDataBounds(Min, Max)` freezes the whole frame (streaming); `AutoScale`
  clears both.
- `ShowGrid` draws grid lines and a faint fill (`GridColor`, `PaneColor`) on the
  three back faces of the box; `ShowCube`, `ShowAxes`, `ShowTicks`, `ShowValues`.
- `Theme := thLight` (default) or `thDark` switches background, box, axis, text
  and grid colours together; each can still be set individually afterwards.

## View and interaction

| Gesture | Effect |
| --- | --- |
| Left-drag | Rotate: horizontal = azimuth, vertical = elevation (±90°) |
| Right-drag, or Shift + left-drag | Pan |
| Wheel | Zoom about the pointer |
| Click | `OnPointPicked(Sender, Series, Index, X, Y, Z)` for the nearest point within `PickTolerance` px |
| Hover | Read-out of the nearest point (and its value) — `ShowHoverInfo` |
| Double-click | Property editor |
| Ctrl + double-click | Reset the view |
| Right-click (no drag) | Menu: copy image, export PNG / PDF, save / load plot, reset, properties |
| Arrow keys | Rotate 5° |
| `+` / `-` | Zoom |
| `R` | Reset view |
| `1`–`4` | Isometric, top, front, side |

The view is plain properties a host can set and save: `Azimuth`, `Elevation`
(degrees, MATLAB `view(az, el)` convention, z up), `Zoom`, `PanX`, `PanY`
(fractions of the plot size), `Projection` (`ppPerspective` /
`ppOrthographic`). `SetView(az, el)`, `ViewPreset(vpIsometric | vpTop | vpFront
| vpSide)`, `ResetView`. `OnViewChanged` fires on every change.

While dragging, large data is drawn at reduced detail (a coarser surface grid,
every k-th point of long curves) and redrawn in full on release
(`ReducedDetail` exposes the switch).

## Legend

Lists series with a `Title` (and `ShowInLegend`) with a line, marker or
colour-map swatch. `LegendVisible`, `LegendLocation` (`llTopRight`,
`llTopLeft`, `llBottomRight`, `llBottomLeft`). Drag it to move it; click an
entry to hide or show its series (hidden entries are dimmed). Hiding a series
never rescales the axes.

## Animation and streaming

- `AutoRotate` / `AutoRotateSpeed` (°/s).
- `RevealFraction` (0..1) draws curves progressively; `AnimateReveal(Seconds)`
  animates it; `ShowRevealHead` marks the current head (also handy while
  streaming).
- Streaming: `Series.AddPoint(x, y, z)` (or add to `Points` and call `Changed`),
  with `SetDataBounds` so the frame doesn't rescale.

## Export and persistence

```pascal
Plot.SaveToPNG('plot.png');                  // on-screen size x screen scale (sharp on HiDPI)
Plot.SaveToPNG('plot.png', 2400, 1600);      // exactly 2400 x 1600 px, laid out like the screen
Plot.SaveToPNG('cut.png', 0, 0, True);       // transparent background
Plot.SaveToPDF('plot.pdf');                  // vector, page = on-screen size in points
Plot.CopyToClipboard;
img := Plot.MakeImage(1200, 900);            // ISkImage, no file

Plot.SavePlotToFile('plot.json');            // whole state: data, style, view, axes, legend, theme
Plot.LoadPlotFromFile('plot.json');
obj := Plot.SaveToJson;  Plot.LoadFromJson(obj);
```

All exports use the same render path as the screen. The JSON is versioned
(`"version": 1`), tolerant of missing keys (older files still load), stores
colours as `#AARRGGBB` and NaN as `null`, and writes doubles so they read back
exactly — a reloaded plot renders pixel-identically.

## Performance

Normalised points, per-point and per-face colours and face normals are cached;
a view change only re-projects and re-sorts. Large surfaces (> 6000 faces) are
drawn as one triangle batch. Measured on the development laptop at 150 % scale
(1040 × 610 control, 1560 × 915 physical pixels):

| Scene | Full detail | While rotating |
| --- | --- | --- |
| 100,000-point curve | 81 ms | 27 ms (37 fps) |
| 200 × 200 surface (40,000 faces) | 41 ms (24 fps) | 18 ms (56 fps) |
| 61 × 61 surface | 14 ms | 14 ms |
| 8,000-point Lorenz | 11 ms | 12 ms |

Known limit: faces are depth-sorted (painter's algorithm), so intersecting
surfaces cannot always be ordered correctly.

## Testing

- `Tests/run_tests.bat` — unit tests for normalisation, aspect, projection
  (known points to known pixels), ticks, colour maps and the JSON helpers.
- Build the demo with `/p:DCC_Define=EXPORT_SELFTEST` and run it: it exports
  every demo scene to PNG, PDF and JSON, reloads each JSON into a fresh plot
  and checks the reload renders pixel-identically, drives the mouse and
  keyboard handlers, times rendering, and writes
  `Win64\Debug\selftest_out\results.txt`, then exits.

## Units

| Unit | Role |
| --- | --- |
| `Rho3DPlot.pas` | `TRho3DPlot` and `TRho3DSeries` |
| `Rho3DTransform.pas` | Normalisation, camera / projection, nice ticks (no FMX) |
| `Rho3DColorMaps.pas` | Colour maps and colour helpers |
| `Rho3DJsonUtils.pas` | JSON helpers |
| `Rho3DPlotEditor.pas` | Run-time property editor (built in code) |
| `Rho3DPlotRegister.pas` | Design-time registration |

## License

MIT — see [LICENSE](LICENSE).
