//--------------------------------------------------------------------------------------------------
// AutoLogon
//    © 2026 Remus Rigo
//       v1.0 2026-05-12
// About form
//--------------------------------------------------------------------------------------------------

unit wndAbout;

interface

uses
   Winapi.Windows, Winapi.Messages, Winapi.ShellAPI,
   System.SysUtils, System.Variants, System.Classes,
   Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Imaging.pngimage;

type
   TfrmAbout = class(TForm)
    lblAppName: TLabel;
      lblVer: TLabel;
      imgPayPal: TImage;
      imgRevolut: TImage;
    lblAuth: TLabel;
      procedure FormCreate(Sender: TObject);
    procedure lblAuthClick(Sender: TObject);
    procedure lblAuthMouseEnter(Sender: TObject);
    procedure lblAuthMouseLeave(Sender: TObject);
      private
      public
end;

var
   frmAbout: TfrmAbout;

implementation

{$R *.dfm}

uses
   appData;

procedure TfrmAbout.FormCreate(Sender: TObject);
begin
   lblAppName.Caption:=appName;
   lblVer.Caption:=appVer;
   lblAuth.Caption:=appAuth;
   lblAuth.Font.Color:=clBlue;
   lblAuth.Cursor:=crHandPoint;
end;

procedure TfrmAbout.lblAuthMouseEnter(Sender: TObject);
begin
   lblAuth.Font.Style:=lblAuth.Font.Style + [fsUnderline];
   lblAuth.Font.Color:=clHighlight;
end;

procedure TfrmAbout.lblAuthMouseLeave(Sender: TObject);
begin
   lblAuth.Font.Style:=lblAuth.Font.Style - [fsUnderline];
   lblAuth.Font.Color:=clBlue;
end;

procedure TfrmAbout.lblAuthClick(Sender: TObject);
begin
   // Parameter 1: Parent window handle (0 or Self.Handle)
   // Parameter 2: The operation ('open')
   // Parameter 3: The URL or file path
   // Parameter 4: Parameters (nil for web links)
   // Parameter 5: Directory (nil)
   // Parameter 6: Show command (SW_SHOWNORMAL = 1)
   ShellExecute(0, 'open', PChar('https://github.com/RemusRigo'), nil, nil, SW_SHOWNORMAL);
end;

end.
