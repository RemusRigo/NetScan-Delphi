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
   System.SysUtils, System.Variants, System.Classes, System.Threading, System.SyncObjs,
   Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, Vcl.StdCtrls, System.ImageList, Vcl.ImgList, Vcl.Menus,
   PercentProgressBar, Vcl.ExtCtrls;

type
   TfrmNetScan = class(TForm)
      mnuNetScan           : TMainMenu;
      popMnuListView       : TPopupMenu;
      imgListStatus        : TImageList;
      mnuNetScan_File      : TMenuItem;
      mnuNetScan_File_Exit : TMenuItem;
      mnuNetScan_View      : TMenuItem;
      mnuNetScan_About     : TMenuItem;
    pnlView: TPanel;
    pnlOptions: TPanel;
    lvNetScan: TListView;
    btnScan: TButton;
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure btnScanClick(Sender: TObject);
    procedure mnuNetScan_AboutClick(Sender: TObject);
    private
      itemsMin   : Integer;
      itemsMax   : Integer;
      percent    : Integer;
      isScanning : Boolean;
      appExit    : Boolean;
      bkTask     : ITask;
      pbPercent  : TPercentProgressBar;
      procedure AutosizeListViewColumns(lv: TListView);
      function  IPToDWORD(const AIP: string): DWORD;
      function  PingIP(TargetAddr: DWORD): Boolean;
      function  GetHostName(TargetAddr: DWORD): string;
      function  GetMAC(TargetAddr: DWORD): string;
      procedure ScanRange(baseIP: String; minIP, maxIP: Integer);
   public
end;

var
   frmNetScan: TfrmNetScan;

implementation

{$R *.dfm}

uses
   iphlpapi_dll,
   appData,
   wndAbout;

//-------------------------------------------------------------------------------------------------
// AutosizeListViewColumns
procedure TfrmNetScan.AutosizeListViewColumns(lv: TListView);
begin
   lv.Items.BeginUpdate;
   try
      for var i := 0 to lv.Columns.Count - 1 do
         lv.Columns[i].Width:=-1; // -1 autosizes based on the content of the items
   finally
      lv.Items.EndUpdate;
   end;
end;

//-------------------------------------------------------------------------------------------------
// IPToDWORD
function TfrmNetScan.IPToDWORD(const AIP: string): DWORD;
begin
   // All the messy Ansi and Pointer casting is now neatly quarantined here!
   Result := inet_addr(PAnsiChar(AnsiString(AIP)));
end;

//-------------------------------------------------------------------------------------------------
// PingIP
function TfrmNetScan.PingIP(TargetAddr: DWORD): Boolean;
var
   IcmpHandle: THandle;
   ReplyBuffer: array[0..255] of Byte; // Extra padding required for ICMP headers
   EchoReply: ^ICMP_ECHO_REPLY;
begin
   Result := False;

   // Open an isolated kernel handle for this thread's ping
   IcmpHandle := IcmpCreateFile;
   if IcmpHandle = INVALID_HANDLE_VALUE then Exit;

   try
      // Send request with a 500ms timeout
      if IcmpSendEcho(IcmpHandle, TargetAddr, nil, 0, nil, @ReplyBuffer[0], SizeOf(ReplyBuffer), 500) > 0 then
      begin
         EchoReply := @ReplyBuffer[0];
         // Status = 0 means IP_SUCCESS
         // "Destination Host Unreachable" or timeouts will be > 0.
         Result := (EchoReply^.Status = 0);
      end;
   finally
      IcmpCloseHandle(IcmpHandle);
   end;
end;

//-------------------------------------------------------------------------------------------------
// GetHostName (Optimized)
function TfrmNetScan.GetHostName(TargetAddr: DWORD): string;
var
   HostEnt: PHostEnt;
begin
   Result := 'Unknown';

   HostEnt := gethostbyaddr(@TargetAddr, SizeOf(TargetAddr), AF_INET);
   if Assigned(HostEnt) then
      Result := string(AnsiString(HostEnt^.h_name));
end;

//-------------------------------------------------------------------------------------------------
// GetMAC (Optimized)
function TfrmNetScan.GetMAC(TargetAddr: DWORD): string;
var
   MacAddr: array[0..5] of Byte;
   MacLen: DWORD;
begin
   Result := 'Unknown';
   MacLen := SizeOf(MacAddr);

   if SendARP(TargetAddr, 0, @MacAddr[0], MacLen) = 0 then
   begin
      Result := Format('%.2x-%.2x-%.2x-%.2x-%.2x-%.2x', [MacAddr[0], MacAddr[1], MacAddr[2], MacAddr[3], MacAddr[4], MacAddr[5]]);
   end;
end;


//-------------------------------------------------------------------------------------------------
// ScanRange
procedure TfrmNetScan.ScanRange(baseIP: String; minIP, maxIP: Integer);
begin
   // Create local safe variable for the thread capture to use
   itemsMin:=minIP;
   itemsMax:=maxIP;
   var localBaseIP:=baseIP + '.';
   var totalIPs:=(maxIP - minIP) + 1;

   isScanning:=True;
   appExit:=False;
   BtnScan.Enabled:=False;
   AutosizeListViewColumns(lvNetScan); // Autosize columns

   // Initialize ProgressBar
   pbPercent.Min:=0;
   pbPercent.Max:=totalIPs;
   pbPercent.Position:=0;

   // Pre-populate the ListView to avoid UI creation conflicts across threads
   lvNetScan.Items.BeginUpdate;
   try
      lvNetScan.Items.Clear;
      for var i := itemsMin to itemsMax do
      begin
         var item:=lvNetScan.Items.Add;
         item.Caption:='Pending';
         item.SubItems.Add(localBaseIP + i.ToString);
         Item.SubItems.Add('');
         Item.SubItems.Add('');
         item.ImageIndex := 1;
      end;
   finally
      lvNetScan.Items.EndUpdate;
   end;

   var CompletedCount:=0;

   // Run the scan asynchronously so the UI doesn't freeze
   bkTask:=TTask.Run(Procedure
   begin
      TParallel.For(itemsMin, itemsMax, Procedure(index: Integer)
      var
         CurrentIP : String;
         IsOnline  : Boolean;
         TargetAddr: DWORD;
         HostName  : String;
         MacAddr   : String;
      begin
         if appExit then Exit;

         CurrentIP:=localBaseIP + Index.ToString;
         TargetAddr:=inet_addr(PAnsiChar(AnsiString(CurrentIP)));
         if TargetAddr = INADDR_NONE then Exit;
         IsOnline:=PingIP(TargetAddr);

         if appExit then Exit;

         if IsOnline then
         begin
            HostName := GetHostName(TargetAddr);
            MacAddr := GetMAC(TargetAddr);
         end
         else
         begin
            HostName := '---';
            MacAddr := '---';
         end;

         var currentProgress:=TInterlocked.Increment(CompletedCount);

         //  Update the UI safely from the main thread
         TThread.Queue(nil, procedure
         begin
            if appExit then Exit;

            pbPercent.Position:=currentProgress;

            // Calculate precise offsets based on the minIP starting value
            var targetIndex := Index - itemsMin;
            if (targetIndex >= 0) and (targetIndex < lvNetScan.Items.Count) then
            begin
               var Item := lvNetScan.Items[targetIndex];

               Item.SubItems[1] := HostName;
               Item.SubItems[2] := MacAddr;

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

            // Ensure scan is 100% complete
            pbPercent.Position:=pbPercent.Max;
         end;
      end);
   end);
end;

//-------------------------------------------------------------------------------------------------
// frmNetScan onCreate
procedure TfrmNetScan.FormCreate(Sender: TObject);
begin
   Self.Caption:=appCaption;

   // initialize PercentProgressBar
   pbPercent:=TPercentProgressBar.Create(Self);
   pbPercent.Parent:=pnlView;
   pbPercent.Left:=2;
   pbPercent.Top:=lvNetScan.Height;
   pbPercent.Height:=18;
   pbPercent.Width:=lvNetScan.Width-4;
   pbPercent.Anchors:=[akLeft, akRight, akBottom];
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

   CanClose:=False; // Stymie the closure for a brief moment
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

//-------------------------------------------------------------------------------------------------
// btnScan onClick
procedure TfrmNetScan.btnScanClick(Sender: TObject);
begin
   ScanRange('192.168.100', 1, 255);
end;

//-------------------------------------------------------------------------------------------------
// mnuNetScan_About onClick
procedure TfrmNetScan.mnuNetScan_AboutClick(Sender: TObject);
var
   frm: TForm;
begin
   frm:=TfrmAbout.Create(nil);
   try
      frm.ShowModal;
   finally
      frm.Free;
   end;
end;

end.

