# TRho3DPlot — a Skia-backed 3D plotting component for Delphi FireMonkey

A 3D plotting control for RAD Studio **FireMonkey (FMX)**, rendered with the
**Skia** backend. `TRho3DPlot` draws 3D curves (such as the Lorenz, Rössler and
Chua attractors) that the user can rotate, zoom and pan, with a bounding box,
axes, ticks and titles, and PNG / PDF export.

It is the 3D companion to the 2D chart `TSkPlotPaintBox`
([Plot2DComponent](https://github.com/hsauro/Plot2DComponent)).

This code was developed using a combination of human effort and AI assistance.

---

## Building

Requires RAD Studio 13 (BDS 37.0) with Skia enabled.

| File | Purpose |
| --- | --- |
| `Rho3DPlot.pas` | The component |
| `ufMain.pas` / `ufMain.fmx` | Demo form |
| `Plotter3DProject.dproj` | Demo application (Win64) |

```cmd
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
msbuild Plotter3DProject.dproj /t:Build /p:Config=Debug /p:Platform=Win64
```

## Quick start

```pascal
uses Rho3DPlot;

Plot := TRho3DPlot.Create(Self);
Plot.Parent := Self;
Plot.Align := TAlignLayout.Client;
Plot.SetPlotData(X, Y, Z);        // one curve through (x, y, z)
```

## Interaction

| Gesture | Effect |
| --- | --- |
| Left-drag | Rotate |
| Right-drag, or Shift + left-drag | Pan |
| Wheel | Zoom |

## License

MIT — see [LICENSE](LICENSE).
