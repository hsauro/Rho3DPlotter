unit Rho3DPlotRegister;

{ Design-time registration of TRho3DPlot (compiled into Rho3DPlotDesign.bpl). }

interface

procedure Register;

implementation

uses
  System.Classes,
  Rho3DPlot;

procedure Register;
begin
  RegisterComponents('Rhody Controls', [TRho3DPlot]);
end;

end.
