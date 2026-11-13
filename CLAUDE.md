# Rho3DPlotter

A Delphi **FireMonkey (FMX)** component, `TRho3DPlot`, for interactive 3D plots
rendered with **Skia**: curves (Lorenz, Rössler, Chua), scatter, surfaces
`z = f(x, y)` and parametric surfaces, depth-sorted together, with rotate / zoom
/ pan, axes, colour bar, legend, property editor, PNG / PDF export and JSON
persistence. The requirements are in `SPEC.md`; `README.md` is the user-facing
API documentation — update it alongside public API changes.

Published at `github.com/hsauro/Rho3DPlotter` (branch `main`).

## Layout

| File | Role |
|------|------|
| `Rho3DPlot.pas` | `TRho3DPlot` + `TRho3DSeries`. **The deliverable.** |
| `Rho3DTransform.pas` | `TRho3DFrame` (normalise), `TRho3DCamera` (rotate / project), `NiceTicks`, `FormatTick`. No FMX — unit-tested. |
| `Rho3DColorMaps.pas` | Colour-map LUTs, `LerpColor`, `ShadeColor`, `FadeColor`. |
| `Rho3DJsonUtils.pas` | `J*` / `JPut*` helpers (2D-component conventions + NaN-as-null, vectors, matrices, exact double text). |
| `Rho3DPlotEditor.pas` | Run-time property editor, built in code (no `.fmx`). |
| `Rho3DPlotRegister.pas` | `Register` → palette page **Rhody Controls** (design package only). |
| `ufMain.pas` / `ufMain.fmx` | Demo form exercising every feature, plus the `EXPORT_SELFTEST` harness. |
| `Plotter3DProject.dpr` / `.dproj` | Demo application. |
| `Package/` | `Rho3DPlotRuntime` (`{$RUNONLY}`), `Rho3DPlotDesign` (`{$DESIGNONLY}`), `Rho3DPlotGroup.groupproj`. |
| `Tests/` | `Rho3DTests.dpr` console unit tests; `run_tests.bat` builds with `dcc64` and runs. |

The demo creates the plot in code in `TfrmMain.FormCreate` (client-aligned).

## Build

Toolchain is **Delphi 13 = RAD Studio / BDS 37.0** (`C:\Program Files (x86)\Embarcadero\Studio\37.0\`).
Do **not** infer the version from `ProjectVersion` in a `.dproj` — it is stale.

Run msbuild via the **PowerShell tool**, not the Bash tool (the Bash tool mangles
`cmd /c '... && ...'`):
```
$env:BDS="C:\Program Files (x86)\Embarcadero\Studio\37.0"; & cmd.exe /c "`"$env:BDS\bin\rsvars.bat`" && msbuild Plotter3DProject.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /nologo /v:minimal"
```
- Output in `Win64\Debug\`. A good build ends with `NNNN lines, N.NN seconds, ... bytes code`.
- Packages: same, from `Package\` with `Rho3DPlotRuntime.dproj` then `Rho3DPlotDesign.dproj`.
- **Adding a unit** to the component: list it in `Package/Rho3DPlotRuntime.dpk`
  (`contains`) **and** `Package/Rho3DPlotRuntime.dproj` (`<DCCReference>`), and in
  `Plotter3DProject.dpr` + `.dproj`.
- Unit tests: `& cmd.exe /c "<abs path>\Tests\run_tests.bat"` → `N passed, 0 failed`.
- Self-test: build the demo with `/p:DCC_Define=EXPORT_SELFTEST`, run
  `Win64\Debug\Plotter3DProject.exe` (Start-Process, wait for exit), read
  `Win64\Debug\selftest_out\results.txt`. It exports every scene (PNG / PDF /
  JSON), reloads each JSON into a fresh plot and compares pixels, drives the
  input handlers through a test-only `TPlotDriver` descendant, and times frames.
  All lines should be `ok` / `reload identical`; view the PNGs to check layout.

## Architecture of `TRho3DPlot`

`TRho3DPlot = class(TSkCustomControl)`. `Draw` renders into a cached offscreen
`ISkSurface` at `Scene.GetSceneScale` (physical pixels, logical coordinates via
`Canvas.Scale`) and blits it 1:1 — the 2D component's HiDPI approach. Everything
goes through `RenderScene(canvas, dest, clear, overlay, vector)`, shared by the
screen, `MakeImage` / `SaveToPNG` / `CopyToClipboard` and `SaveToPDF`
(`vector=True` → faces always as real paths, never the triangle batch).

**Pipeline** (SPEC §5):
1. `Prepare` (only when `FPrepared` is false — `SeriesChanged` clears it):
   `ComputeBounds` (all series, **visible or not**, so hiding never rescales;
   NaN skipped; fixed limits / `SetDataBounds` override; sets `FClip`) →
   `FFrame.Setup` (aspect → box half-extents `Half[]`, max 1) →
   `ComputeColorRange` (union over colour-mapped series, `ColorMin/Max`
   override) → `PrepareSeries`: box-space `FNorm` (NaN = gap / hole / clipped),
   per-point `FPtColor` (opacity baked in; gradients quantised to 256 steps so
   long runs share a colour), surface faces `FFaces` + coarse `FCoarseFaces`
   (base colour + unit normal). Bars (`PrepareBars`): `FNorm` holds one point
   per bar first (the centre of the end it reaches, so hover / picking index
   bars as surfaces index vertices), then 8 corners per bar at `n + 8 b + k`
   (bit 0 of k = high x, bit 1 = high y, bit 2 = high z); `FFaces` six faces per
   bar shown, in a row, with outward normals.
2. Per frame: `FCam.Prepare(plotRect)`, `TransformSeries` → `FScr` / `FDepth`
   (view Z, larger = nearer) and the reveal head.
3. `BuildItems` → one list of faces, curve chunks, markers and bars (`dkBar`, one
   item per bar, keyed by where it stands: `BarKey`) keyed by depth;
   `SortOrder` (own quicksort on an index array). Curves are one item when no
   surface is visible, otherwise chunked (≤ `MaxCurveItems` total).
4. `DrawScene`: faces as AA paths (fill + seam stroke, or edges), or — when
   > `BatchFaceThreshold` faces and not PDF — appended to a triangle batch
   flushed with `DrawVertices` (edges as thin quads); a bar as its faces turned
   to the viewer (`FacesViewer`; far faces first when translucent); curve chunks as one
   stroked path per colour run (`DrawCurveChunk`); markers. Around it:
   `DrawBoxBack` (panes + grid on back faces), box edges split back / front by
   `ComputeBoxFacing`, `DrawAxis` ×3, colour bar, legend, title, hover.

**Camera** (`Rho3DTransform`): MATLAB `view(az, el)`, z up; view space X right,
Y up, Z toward the viewer. Default az −60°, el 30°. Pan is a fraction of
`Min(w, h)` so exports at other sizes match. `BaseScale` sets the default fit.

**Axes**: ticks per render come from `ComputeTicks`: round numbers (`NiceTicks`), or
the named ticks of `SetTickLabels` (`FTickPos`/`FTickNames`, those inside the
range copied to `FTicks`/`FTickText`, `FTickStep` their smallest gap for the
label thinning; named ticks that would need thinning are drawn across the axis instead,
rotated along u, `across` in `DrawAxis`). Each axis uses the box edge lowest on screen (x, y) or leftmost (z),
tie-broken toward the viewer; ticks / labels go outward in screen space; labels
are thinned if they'd overlap; an axis within ~18° of the line of sight is
skipped.

**Interaction**: `MouseDown` picks a mode (legend / pan / rotate); `MouseMove`
promotes it to a drag past 3 px and sets `FInteracting` (reduced detail:
`PointStride`, coarse faces); `MouseUp` without a drag = click (legend toggle,
`OnPointPicked`, or right-click menu). Hover uses `FindNearestPoint` on the last
screen pass's `FScr`. `FScreenPass` guards state that only the on-screen render
may record (legend rects, `FScreenCenter/FScreenMinWH`); exports call `Redraw`
afterwards to restore the screen-space caches.

**Persistence**: `SaveToJson` / `LoadFromJson` sections `view`, `chart`, `axes`,
`colorBar`, `lighting`, `legend`, `animation`, `style`, `series[]`; enums as
strings (`*Names` arrays); missing keys keep current values. Bump
`Rho3DJsonVersion` on breaking changes.

## Skia API notes (RTL 37.0)

- Text: `DrawSimpleText(text, x, y, font, paint)`; `TSkFont.Create(nil, size)`; `font.MeasureText`.
- Paths: `pb: ISkPathBuilder := TSkPathBuilder.Create; pb.MoveTo/LineTo/Close; pb.Detach` (resets the builder).
- Triangles: `TSkVertices.MakeCopy(TSkVertexMode.Triangles, pos, nil, colors)` →
  `DrawVertices(v, TSkBlendMode.Modulate, whitePaint)`. Not used for PDF.
- `ISkSurface` has no Width/Height — track them yourself.
- PNG: `TSkSurface.MakeRaster` → `MakeImageSnapshot` → `EncodeToFile(name, PNG)`.
  PDF: `TSkDocument.MakePDF(stream, metadata)` → `BeginPage` → `EndPage` → `Close`.
- Clipboard: `IFMXClipboardService` is in `FMX.Platform`; `SkImageToBitmap` in `FMX.Skia`.

## Gotchas / conventions

- `TRho3DSeries` fields are `private` (not `strict private`) so the plot can use
  them directly (same-unit friendship).
- `Power(10, n)` picks the **Single** overload — use `Power(Double(10), n)`.
- `TJSONNumber.Create(Double)` keeps only 15 digits; `FloatToJson` writes the
  shortest exact text so reloads are pixel-identical (sort ties on symmetric
  translucent surfaces otherwise flip).
- JSON files are written UTF-8 **without** BOM; the loader tolerates one.
- In the `TRho3DPlot` declaration the first `type` block (enums, aliases) is
  separated from the forward declarations by the re-exported enum `const`s —
  forward class declarations must stay in the same `type` block as the classes.
- Demo enums `TDemoMode` / `TStreamKind` are cast from `cmbMode.ItemIndex` /
  `cmbSource.ItemIndex` — **enum order must match the combo items** in `ufMain.fmx`.
- The demo's draw-style combo is synced with an `FSyncingDraw` guard.
- The colour bar stays while its colour-mapped series is hidden, so the layout (and
  the legend under the pointer) doesn't jump on a legend click.
