//--------------------------------------------------------------------------------------------------
// NetScan
//    © 2026 Remus Rigo
//       v1.0 2026-05-16
// Main form
//--------------------------------------------------------------------------------------------------

unit wndNetScan;

interface

uses
   Winapi.Windows, Winapi.Messages, Winapi.WinSock2,
   System.SysUtils, System.Variants, System.Classes, System.Threading,
   Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, Vcl.StdCtrls, System.ImageList, Vcl.ImgList,
   Vcl.Menus;

type
   TfrmNetScan = class(TForm)
      mnuNetScan: TMainMenu;
      popMnuListView: TPopupMenu;
      lvNetScan: TListView;
      imgListStatus: TImageList;
      btnScan: TButton;
    procedure btnScanClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    private
      isScanning: Boolean;
      appExit: Boolean;
      bkTask: ITask;
      procedure AutosizeListViewColumns(lv: TListView);
      function PingIP(const AIP: string): Boolean;
   public
end;

var
   frmNetScan: TfrmNetScan;

implementation

{$R *.dfm}

uses
   iphlpapi_dll;

//-------------------------------------------------------------------------------------------------
// AutosizeListViewColumns
procedure TfrmNetScan.AutosizeListViewColumns(lv: TListView);
begin
   lv.Items.BeginUpdate;
   try
      for var i := 0 to lv.Columns.Count - 1 do
         lv.Columns[i].Width := -1 // -1 autosizes based on the content of the items
   finally
      lv.Items.EndUpdate;
   end;
end;

//-------------------------------------------------------------------------------------------------
// PingIP
function TfrmNetScan.PingIP(const AIP: string): Boolean;
var
   IcmpHandle: THandle;
   TargetAddr: DWORD;
   ReplyBuffer: array[0..255] of Byte; // Extra padding required for ICMP headers
   EchoReply: ^ICMP_ECHO_REPLY;
begin
   Result := False;

   // Convert string IP into a network-byte DWORD (Requires Winapi.WinSock2)
   TargetAddr := inet_addr(PAnsiChar(AnsiString(AIP)));
   if TargetAddr = INADDR_NONE then Exit;

   // Open an isolated kernel handle for this thread's ping
   IcmpHandle := IcmpCreateFile;
   if IcmpHandle = INVALID_HANDLE_VALUE then Exit;

   try
      // Send request with a 500ms timeout
      if IcmpSendEcho(IcmpHandle, TargetAddr, nil, 0, nil, @ReplyBuffer[0], SizeOf(ReplyBuffer), 500) > 0 then
      begin
         EchoReply := @ReplyBuffer[0];
         // Status = 0 means IP_SUCCESS. "Destination Host Unreachable" or timeouts will be > 0.
         Result := (EchoReply^.Status = 0);
      end;
   finally
      IcmpCloseHandle(IcmpHandle);
   end;
end;

//-------------------------------------------------------------------------------------------------
// btnScan onClick
procedure TfrmNetScan.btnScanClick(Sender: TObject);
const
   IP_BASE = '192.168.100.';
begin
   isScanning:=True;
   appExit:=False;
   BtnScan.Enabled:=False;
   AutosizeListViewColumns(lvNetScan);

   // Pre-populate the ListView to avoid UI creation conflicts across threads
   lvNetScan.Items.BeginUpdate;
   try
      lvNetScan.Items.Clear;
      for var i := 1 to 255 do
      begin
         var Item := lvNetScan.Items.Add;
         Item.Caption := 'Pending';
         Item.SubItems.Add(IP_BASE + i.ToString);
         Item.ImageIndex := 1;
      end;
   finally
      lvNetScan.Items.EndUpdate;
   end;

   // Run the scan asynchronously so the UI doesn't freeze
   TTask.Run(procedure
   begin
      // TParallel.For automatically manages a thread pool for fast scanning
      TParallel.For(1, 255, procedure(Index: Integer)
      var
         CurrentIP: string;
         IsOnline: Boolean;
         begin
            CurrentIP:=IP_BASE + Index.ToString;
            IsOnline:=PingIP(CurrentIP);
            if appExit then Exit;

            //  Update the UI safely from the main thread
            TThread.Queue(nil, procedure
            begin
               if appExit then Exit;

               // ListView is 0-indexed, so Index 1 maps to lvNetScan.Items[0]
               if (Index - 1 < lvNetScan.Items.Count) then
               begin
                  var Item := lvNetScan.Items[Index - 1];
                  if IsOnline then
                  begin
                     Item.Caption := 'Online';
                     Item.ImageIndex := 0; // Green Dot
                  end
                  else
                  begin
                     Item.Caption := 'Offline';
                     Item.ImageIndex := 1; // Gray Dot
                  end;
               end;
            end);
         end);

      // cleanup / parallel loop finishes
      TThread.Queue(nil, procedure
      begin
         isScanning:=False;
         if Not appExit then
         begin
            btnScan.Enabled:=True;
            AutosizeListViewColumns(lvNetScan);
         end;
      end);
   end);
end;

//-------------------------------------------------------------------------------------------------
// frmNetScan onCloseQuesy
procedure TfrmNetScan.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
   // If no scan is running, let the app close instantly
   if not isScanning then
   begin
      CanClose:=True;
      Exit;
   end;

   // Stymie the closure for a brief moment
   CanClose:=False;
   appExit:= True; // Signal all background threads to drop what they are doing

   // Wait safely for the outer task to reach a full stop.
   // Because TParallel.For stops very fast when signaled, this takes milliseconds.
   if Assigned(bkTask) then
   begin
      // ProcessMessages keeps the UI alive during the brief wait loop
      while isScanning do
      begin
         Application.ProcessMessages;
         Sleep(10);
      end;
   end;

   // Everything is cleanly stopped. It is now safe to close.
   CanClose:=True;
end;

end.
