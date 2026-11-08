program Plotter3DProject;

uses
  System.StartUpCopy,
  FMX.Forms,
  FMX.Skia,
  ufMain in 'ufMain.pas' {frmMain},
  Rho3DPlot in 'Rho3DPlot.pas',
  Rho3DTransform in 'Rho3DTransform.pas',
  Rho3DColorMaps in 'Rho3DColorMaps.pas',
  Rho3DJsonUtils in 'Rho3DJsonUtils.pas',
  Rho3DPlotEditor in 'Rho3DPlotEditor.pas';

{$R *.res}

begin
  GlobalUseSkia := True;
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
