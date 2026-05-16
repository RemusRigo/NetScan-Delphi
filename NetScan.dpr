//--------------------------------------------------------------------------------------------------
// NetScan
//    © 2026 Remus Rigo
//       v1.0 2026-05-16
// Main form
//--------------------------------------------------------------------------------------------------

program NetScan;

uses
   Vcl.Forms,
   iphlpapi_dll in 'API\iphlpapi_dll.pas',
   wndNetScan in 'Forms\wndNetScan.pas' {frmNetScan};

{$R *.res}

begin
   Application.Initialize;
   Application.MainFormOnTaskbar := True;
   Application.CreateForm(TfrmNetScan, frmNetScan);
   Application.Run;
end.
