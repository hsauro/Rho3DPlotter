# Rho3DPlot — specification for a full 3D plotting component

Status: draft for a new development session, 2026-11-08.
Owner: Herbert Sauro. Target: Delphi 13 / RAD Studio 37.0, FireMonkey, Skia; Windows (Win64) and macOS (ARM64).

## 1. Purpose

A reusable FMX control for interactive 3D plots, the 3D companion to the 2D chart `TSkPlotPaintBox` (`..\PlottingComponent`, repository Plot2DComponent). It must draw:

- **Parametric curves**: trajectories such as the Lorenz, Rössler and Chua attractors, `(x(t), y(t), z(t))`.
- **Surfaces**: `z = f(x, y)` over a grid, and parametric surfaces `(x(u, v), y(u, v), z(u, v))` such as a torus or sphere.
- **3D scatter**: point clouds, optionally coloured by a value.

All with rotate, zoom and pan, and the finish of the 2D component: axes with ticks and titles, a legend, a property editor, export, and JSON save/load.

The 2D and 3D components stay separate: they share almost no rendering code (projection, depth sorting and rotation have no 2D counterpart), and keeping them apart means applications using the 2D component are unaffected by 3D work.

## 2. Starting point

This folder already holds `TRho3DPlot` (`Rho3DPlot.pas`, about 1,100 lines) and a demo app (`ufMain.pas`, `Plotter3DProject.dproj`). **Extend it; do not start over.** It already has:

- `TRho3DSeries`: a polyline with colour, thickness, start→end colour gradient, lines and/or points, point size, visibility, title.
- Unit-cube normalisation (each axis scaled independently), yaw/pitch rotation, perspective projection, depth value per point.
- Mouse: left-drag rotates, right-drag or Shift+drag pans, wheel zooms; `ResetView`; `AutoRotate` with a speed.
- Bounding cube, axes, ticks, tick values, axis titles; colours for cube, axes, text, background (dark by default).
- Depth cueing of markers; `SetDataBounds` / `AutoScale` for streaming data without rescaling.
- One render path (`RenderScene`) for screen and export; `SaveToPNG` (with optional transparency) and `SaveToPDF` (vector).

See `CLAUDE.md` in this folder for its architecture, build commands and Skia API notes.

**Housekeeping first:** this folder is not yet a git repository. Make it one (with a `.gitignore` for `Win64/`, `__history/`, `*.dcu`, `*.local`, `build.log`), add an MIT `LICENSE` and a `README.md` like the 2D component's, and push it to GitHub as its own repository before the main work.

## 3. Requirements

### 3.1 Series kinds

| Kind | Data | Notes |
| --- | --- | --- |
| Curve (existing) | Points `(x, y, z)` | NaN in any coordinate lifts the pen (a gap), as in the 2D component |
| Scatter | Points `(x, y, z)` | Marker shape (circle, square, diamond, triangle, cross), size; per-point colour from a value |
| Surface | Grid vectors `X[j]`, `Y[i]` and matrix `Z[i, j]` | `z = f(x, y)`; NaN in `Z` leaves a hole (faces touching it are skipped) |
| Parametric surface | Matrices `X[i, j]`, `Y[i, j]`, `Z[i, j]` over a `(u, v)` grid | Spheres, tori, Möbius strips; may close on itself |
| Bars (added 2026-11-13) | Grid vectors `X[j]`, `Y[i]` and matrix `Z[i, j]` | A box at each grid point from 0 to `Z[i, j]` (down for a negative value), `BarWidth` of the grid spacing; NaN leaves no bar |

A plot can hold several series of any kinds together (for example a surface with a trajectory on it).

### 3.2 Colour

- Solid colour; gradient along a curve (existing).
- **Colour maps**: viridis (default), plasma, coolwarm (diverging), gray, jet (for compatibility only). A surface is coloured by height `z` by default, or by a separate value matrix `C[i, j]`; a scatter by a value vector.
- A **colour bar** beside the plot for any colour-mapped series, with ticks and an optional title.
- Colour range: automatic from the data, or fixed (`ColorMin`, `ColorMax`) so several plots share one scale.

### 3.3 Surface rendering

- **Fill modes**: filled faces, wireframe (mesh lines only), or both (filled with thin edges, the default).
- **Shading**: optional flat Lambert lighting (one directional light, adjustable direction, ambient level) multiplied into the face colour, so shape reads even with a single colour.
- **Depth**: faces sorted back to front by depth (painter's algorithm), re-sorted when the view changes. Curves and scatter points are merged into the same depth order (sorted per segment and per point) so a trajectory passes correctly in front of and behind a surface. Known limit: intersecting faces cannot be ordered correctly by sorting alone; acceptable for v1.
- **Transparency**: per-series opacity (0 to 1), for seeing a trajectory through a surface.
- **Contours** (optional, v1 if time allows): contour lines of `z` projected onto the floor of the box, and/or drawn on the surface.

### 3.4 Axes and frame

- Existing cube, axes, ticks and values, now with **round-number ticks** (1, 2, 5 × 10ⁿ) and labels placed on the edges nearest the viewer, as in MATLAB and matplotlib, so they never sit behind the data.
- Axis titles (existing) and a **chart title**.
- **Aspect modes**: independent scaling per axis (existing, the default: fills the cube), equal aspect (one data unit is the same length on every axis, for geometry), or explicit ratios.
- Fixed axis limits per axis (`XMin`…`ZMax` with automatic otherwise), as `AxisLimits` in the 2D component.
- Optional grid planes on the three back faces of the box.
- Light and dark themes: a `Theme` property switching background, box, text and grid colours together (the existing defaults are dark).

### 3.5 Legend

A legend listing titled series with a line, marker or colour swatch, as in the 2D component: draggable, click an entry to hide or show its series, locations top right / top left / bottom right / bottom left.

### 3.6 Interaction

| Gesture | Effect |
| --- | --- |
| Left-drag | Rotate (orbit): horizontal changes azimuth, vertical changes elevation (clamped to ±90°) |
| Right-drag, or Shift + left-drag | Pan |
| Wheel | Zoom about the pointer |
| Double-click | Open the property editor (as the 2D component) |
| Ctrl + double-click | Reset the view |
| Keyboard (when focused) | Arrow keys rotate in 5° steps, `+`/`-` zoom, `R` reset, `1`–`4` preset views |
| Hover | Read-out of the nearest data point's `(x, y, z)` (and value), with an `OnPointPicked` event on click carrying the series and index |

Preset views: isometric (azimuth −60°, elevation 30°, the default), top (looking down `z`), front (`x`–`z`), side (`y`–`z`). The view is exposed as properties `Azimuth`, `Elevation` (degrees), `Zoom`, `PanX`, `PanY` so a host can set and save it. **Orthographic** projection as an alternative to perspective (`Projection = ppOrthographic`), the better choice for reading values.

While dragging, large data may be drawn at reduced detail (every k-th face or point) and redrawn in full when the mouse is released, to keep rotation smooth.

### 3.7 Animation

- **Auto-rotate** (existing).
- **Trajectory reveal**: draw a curve progressively (`RevealFraction` 0 to 1, or an `AnimateReveal(Seconds)` method), useful for showing how an attractor forms. Optionally a marker at the current head of the curve.
- Streaming points (existing `AddPoint` with `SetDataBounds`).

### 3.8 Export and persistence

- `SaveToPNG` (existing; must render at the requested pixel size and at the screen's scale on HiDPI displays) and `SaveToPDF` (existing, vector). Right-click menu with Copy image, Export PNG, Export PDF, as in the 2D component.
- **JSON**: `SaveToJson` / `LoadFromJson` and `SavePlotToFile` / `LoadPlotFromFile` with the whole state (series data and style, colour maps, view, axes, legend, theme), versioned, and tolerant of missing keys so older files still load. Follow the 2D component's conventions (`uPlotJsonUtils`-style helpers; colours as `#AARRGGBB`).

### 3.9 Property editor

A run-time tabbed editor opened on double-click, like `ufPlotEditor` in the 2D component: General (titles, theme, projection, aspect), Axes (limits, ticks, grid planes, box), Series (per-series colour, colour map, fill mode, opacity, line width, markers), Lighting, Legend. Changes apply live.

### 3.10 Display quality and performance

- **HiDPI**: render at physical resolution (the 2D component's approach: an offscreen surface at `Scene.GetSceneScale`, drawn 1:1), so lines and text are sharp at 150 % and on Retina.
- Antialiased lines; no visible seams between filled faces (draw each face's fill slightly overlapping, or fill and stroke edges in the face colour).
- Targets, on a typical laptop: a 100,000-point curve rotates smoothly (at least 30 frames per second); a 200 × 200 surface (about 40,000 faces) rotates at no less than 15 frames per second at full detail. Cache normalised points and per-face colours; recompute only the projection and sort on a view change.

## 4. API sketch

Names are suggestions; keep the existing ones where they already exist.

```pascal
type
  TRho3DSeriesKind = (skCurve, skScatter, skSurface, skParametricSurface, skBars);
  TRho3DFillMode   = (fmFilled, fmWireframe, fmFilledWithEdges);
  TRho3DColorMap   = (cmViridis, cmPlasma, cmCoolwarm, cmGray, cmJet);
  TRho3DProjection = (ppPerspective, ppOrthographic);
  TRho3DAspect     = (asIndependent, asEqual, asCustom);

  TRho3DSeries = class
    // existing curve members (Points, Color, Thickness, UseGradient, ...)
    property Kind: TRho3DSeriesKind;
    property Opacity: Single;                       // 0..1
    property ColorMap: TRho3DColorMap;
    property ColorByValue: Boolean;                 // colour-map instead of solid colour
    property MarkerShape: TRho3DMarker;             // scatter
    // surfaces
    procedure SetSurface(const X, Y: array of Double; const Z: TArray<TArray<Double>>);
    procedure SetParametricSurface(const X, Y, Z: TArray<TArray<Double>>);
    procedure SetBars(const X, Y: array of Double; const Z: TArray<TArray<Double>>;
      const AWidth: Single = 0.8);
    property BarWidth: Single;                      // fraction of the grid spacing
    procedure SetValues(const C: TArray<TArray<Double>>);   // optional colour values
    property FillMode: TRho3DFillMode;
    property EdgeColor: TAlphaColor;
    property EdgeWidth: Single;
    property Shaded: Boolean;                       // Lambert lighting
  end;

  TRho3DPlot = class(TSkCustomControl)
    function AddSurface(const X, Y: array of Double; const Z: TArray<TArray<Double>>): TRho3DSeries;
    function AddBars(const X, Y: array of Double; const Z: TArray<TArray<Double>>;
      const AWidth: Single = 0.8): TRho3DSeries;
    function AddCurve(const X, Y, Z: array of Double): TRho3DSeries;
    function AddScatter(const X, Y, Z: array of Double): TRho3DSeries;
    procedure SetView(AAzimuth, AElevation: Single);
    procedure ViewPreset(APreset: TRho3DViewPreset);
    function SaveToJson: TJSONObject;
    procedure LoadFromJson(const Obj: TJSONObject);
    procedure SavePlotToFile(const FileName: string);
    procedure LoadPlotFromFile(const FileName: string);
    property Azimuth, Elevation, Zoom, PanX, PanY: Single;
    property Projection: TRho3DProjection;
    property Aspect: TRho3DAspect;
    property ChartTitle: string;
    property ShowColorBar: Boolean;
    property ColorMin, ColorMax: Double;            // NaN = automatic
    property LightAzimuth, LightElevation, Ambient: Single;
    property LegendVisible: Boolean;
    property Theme: TRho3DTheme;                    // dark / light
    property OnPointPicked: TRho3DPointPicked;
  end;
```

## 5. Rendering pipeline

1. **Prepare** (on data change): normalise every point to the unit cube under the aspect mode; build faces for surfaces (two triangles or one quad per grid cell, skipping NaN corners), their colour-map values, and normals.
2. **Transform** (on view change): rotate and project every point; compute each face's and segment's depth (mean of its corners).
3. **Sort**: one list of drawables (faces, curve segments, points) by depth, far to near. A bar is one drawable, keyed by where it stands (the depth of its foot on the base plane; with perspective, its distance from the eye across the ground): bars stand on one plane and never overlap there, so whole bars in that order hide each other correctly, where their faces sorted one by one would not. Each bar draws only its faces turned towards the viewer (a translucent one draws its far faces first).
4. **Draw**: back box faces and grid planes, then the drawables in order (applying shading and opacity), then the front box edges, axes, ticks and labels, colour bar, legend, title.
5. **Export** goes through the same path with a different canvas and size.

## 6. Axon integration (later, in the Axon repository)

Once the component works on its own:

- The `plot` module gains `plot.line3(x, y, z; ...)` and `plot.scatter3(x, y, z; ...)`; `plot.surface` already exists. Figures with these series become 3D figures (a 2D and a 3D figure cannot mix, as now).
- `plot.show` passes 3D figures to `graphics.show` as data, as it already does for 2D figures; the IDE's plot pane gets a second chart (`TRho3DPlot`) beside `TSkPlotPaintBox`, with a loader like `ide/uFigureChart.pas`.
- An example, such as the Lorenz attractor solved with `ode.solve` and drawn with `plot.line3`.
- The README's clone list gains this repository (folder `RhodyComponents/Rho3DPlotter`).

## 7. Testing

- The demo app shows every feature: a Lorenz trajectory, a `z = sin(r)/r` surface, a parametric torus, a scatter coloured by value, a surface with a curve on it, the colour bar, each preset view, both projections, light and dark themes, export.
- A headless self-test (as the existing `EXPORT_SELFTEST` define) exports PNG, PDF and JSON, reloads the JSON, and checks the reload exports the same PNG.
- Projection and normalisation have small unit tests (known points map to known pixels for a given view).
- Each existing feature still works: rotate, pan, zoom, auto-rotate, gradients, streaming, export.
- Check HiDPI sharpness on Windows at 150 % and on a Retina Mac.

## 8. Out of scope for v1

Volume rendering, isosurfaces, 3D vector fields (quiver), lighting with specular highlights or shadows, GPU rendering, and correct drawing of intersecting surfaces (would need splitting faces or a z-buffer).

## 9. Open questions

1. Rename the component (for example `TSkPlot3D`, to sit beside `TSkPlotPaintBox`), or keep `TRho3DPlot`?
2. Default theme: keep the dark background, or default to light to match the 2D component and printed figures?
3. Should the property editor share code with the 2D editor (a common unit), or stay separate to keep the components independent?
4. Packaging: a run-time and design-time package and palette registration, like the 2D component, or source-only for now?

### Decisions (2026-11-08)

1. Keep `TRho3DPlot`.
2. Default theme is **light**; `Theme := thDark` gives the previous look.
3. The property editor is separate (`Rho3DPlotEditor.pas`, built in code, standard FMX controls only), so the 3D component has no dependency on the 2D one or on `LabelTrackBarRuntime`.
4. Run-time and design-time packages (`Package/Rho3DPlotRuntime`, `Package/Rho3DPlotDesign`), palette page **Rhody Controls**.
