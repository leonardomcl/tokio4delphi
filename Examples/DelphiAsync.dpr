program DelphiAsync;

uses
  Vcl.Forms,
  Principal in 'Principal.pas' {FPrincipal},
  Tokio.Async.Bridge in 'Tokio.Async.Bridge.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TFPrincipal, FPrincipal);
  Application.Run;
end.
