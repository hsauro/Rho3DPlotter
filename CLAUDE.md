# Rho3DPlotter

A Delphi **FireMonkey (FMX)** application and reusable component for plotting
3D line/scatter data with **Skia**. Built to draw things like the Lorenz,
Rössler and Chua attractors as 3D curves that the user can rotate, zoom and pan.

## Layout

| File | Role |
|------|------|
| `Rho3DPlot.pas` | The reusable component. **This is the deliverable.** |
| `ufMain.pas` / `ufMain.fmx` | Demo form that exercises every feature. |
| `Plotter3DProject.dpr` / `.dproj` | Demo application project. |

The component is created in code in `TfrmMain.FormCreate` (client-aligned),
not dropped on the form at design time. `TRho3DPlot` does have a `Register`
procedure, so it *can* be installed into a design-time package later.

## Build

Toolchain is **Delphi 13 = RAD Studio / BDS 37.0** (`C:\Program Files (x86)\Embarcadero\Studio\37.0\`).
Do **not** infer the version from `ProjectVersion` in the `.dproj` — it is stale.

Command line (source `rsvars.bat` first, wrap in `cmd /c` so its env survives):

```
cmd /c '"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild Plotter3DProject.dproj /t:Build /p:Config=Debug /p:Platform=Win64'
```

- Default Config/Platform: `Debug` / `Win64`; output in `Win64\Debug\`.
- A good build ends with `NNNN lines, N.NN seconds, ... bytes code` and `0 Error(s)`.
- On Windows, run msbuild via the **PowerShell tool**, not the Bash tool — the
  Bash tool mangles the `cmd /c '... && ...'` invocation (an interactive banner
  swallows msbuild output). PowerShell form that works:
  ```
  & cmd.exe /c "`"$env:BDS\bin\rsvars.bat`" && msbuild Plotter3DProject.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /nologo"
  ```

## Architecture of `TRho3DPlot`

`TRho3DPlot = class(TSkCustomControl)`. Rendering is done by overriding the
protected `Draw`, which delegates to `RenderScene(canvas, dest, clearColor)` —
the single render path shared by on-screen painting **and** PNG/PDF export, so
exports are pixel-identical to the screen.

**Data model:** a `TObjectList<TRho3DSeries>`. Each `TRho3DSeries` is one
polyline with its own `Color`, `Thickness`, `UseGradient` (+ gradient colors),
`ShowLine`, `ShowPoints`, `PointSize`, `Visible`, `Title`, and a
`Points: TList<TPoint3D>`. Series notify the plot via `SeriesChanged`.

**Coordinate pipeline** (per point): `Normalize` maps data into the unit cube
`[-1..1]³` (each axis scaled independently, across all visible series) →
`Rotate` (yaw about Y, then pitch about X, manual sin/cos) → `ProjectRotated`
(perspective divide with camera `FDistance`). `ProjectRotated` also yields
view-space depth (`R.Z`, larger = nearer), used for depth-cued markers.

**Bounds:** computed lazily in `EnsureBounds` (called from `RenderScene`, so it
works with axes off). `SetDataBounds(min,max)` freezes the frame (used while
streaming so it doesn't rescale); `AutoScale` re-enables fitting.

**Interaction:** mouse in overridden `MouseDown/Move/Up/Wheel` (left=rotate,
right or Shift+left=pan, wheel=zoom). Auto-rotate is an internal `TTimer`
(`AutoRotate`, `AutoRotateSpeed` °/s); it yields while the user is dragging.

**Master properties:** plot-level `LineColor`, `LineThickness`, `UseGradient`,
gradient colors, `ShowLines`, `ShowPoints`, `PointSize`, `DepthCue` propagate to
**every** series and seed newly-added ones. Frame appearance: `ShowCube`,
`ShowAxes`, `ShowTicks`, `ShowValues`, `TickCount`, `CubeColor`, `AxisColor`,
`TextColor`, `BackgroundColor`, `AxisTitleX/Y/Z`.

**Export:** `SaveToPNG(file, w, h, transparent)` — raster via `TSkSurface`,
`transparent=True` clears with `TAlphaColors.Null` for an alpha cut-out.
`SaveToPDF(file, w, h)` — vector via `TSkDocument.MakePDF` (scalable, for
publications). `w=h=0` means use the control's on-screen size.

## Skia API notes (RTL 37.0)

- Text: `ISkCanvas.DrawSimpleText(text, x, y, font, paint)`; `TSkFont.Create(nil, size)`;
  measure with `font.MeasureText`.
- Polyline: `DrawPoints(TSkDrawPointsMode.Polygon, pts, paint)`; single segments
  `DrawLine`; markers `DrawCircle`. Paint styles: `TSkPaintStyle.Stroke/Fill`.
- PNG: `TSkSurface.MakeRaster(w,h)` → `surface.MakeImageSnapshot` →
  `image.EncodeToFile(name, TSkEncodedImageFormat.PNG)`.
- PDF: `TSkDocument.MakePDF(stream, TSkPDFMetadata.Create(...))` →
  `BeginPage(w,h)` returns the canvas → `EndPage` → `Close`.

## Gotchas / conventions

- `TRho3DSeries` fields are `private` (not `strict private`) on purpose so the
  master setters on `TRho3DPlot` can write them directly (same-unit friendship).
- Series/plot method named `SetPlotData` (not `SetData`) to avoid hiding
  `TFmxObject.SetData`.
- Demo enums `TDemoMode` / `TStreamKind` are cast directly from
  `cmbMode.ItemIndex` / `cmbSource.ItemIndex` — **enum order must match the
  combo `Items.Strings` order** in `ufMain.fmx`.
- The demo's draw-style combo is kept in sync programmatically with an
  `FSyncingDraw` guard so the sync doesn't re-trigger a rebuild.
- Verifying export end-to-end: temporarily call `SaveToPNG/PDF` under an
  `{$IFDEF EXPORT_SELFTEST}` in `FormCreate`, build with
  `/p:DCC_Define=EXPORT_SELFTEST`, run headless-ish, inspect the files, then
  remove the scaffolding.
