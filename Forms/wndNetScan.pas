//--------------------------------------------------------------------------------------------------
// NetScan
//    © 2026 Remus Rigo
//       v1.0 2026-05-17
// Main form
//--------------------------------------------------------------------------------------------------

unit wndNetScan;

interface

uses
   Winapi.Windows, Winapi.Messages, Winapi.WinSock2,
   System.SysUtils, System.Variants, System.Classes, System.Threading, System.SyncObjs,
   Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, Vcl.StdCtrls, System.ImageList, Vcl.ImgList, Vcl.Menus,
   PercentProgressBar, Vcl.ExtCtrls, Vcl.ToolWin;

type
   TViewMode = (vmAll, vmOnline, vmOffline);

   TScanResult = record
      Status    : string;
      IP        : string;
      HostName  : string;
      macAddr   : string;
      ImageIndex: Integer;
   end;

   TfrmNetScan = class(TForm)
      mnuNetScan             : TMainMenu;
      popMnuListView         : TPopupMenu;
      imgListStatus          : TImageList;
      mnuNetScan_File        : TMenuItem;
      mnuNetScan_File_Exit   : TMenuItem;
      mnuNetScan_View        : TMenuItem;
      mnuNetScan_View_All    : TMenuItem;
      mnuNetScan_View_Online : TMenuItem;
      mnuNetScan_View_Offline: TMenuItem;
      mnuNetScan_About       : TMenuItem;
      ToolBar1               : TToolBar;
      ToolButton2: TToolButton;
      cbView                 : TComboBox;
      pnlView                : TPanel;
      pnlOptions             : TPanel;
      lvNetScan              : TListView;
      btnScan                : TButton;
      procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
      procedure FormCreate(Sender: TObject);
      procedure btnScanClick(Sender: TObject);
      procedure mnuNetScan_AboutClick(Sender: TObject);
      procedure mnuNetScan_View_AllClick(Sender: TObject);
      procedure mnuNetScan_View_OnlineClick(Sender: TObject);
      procedure mnuNetScan_View_OfflineClick(Sender: TObject);
      procedure cbViewChange(Sender: TObject);
      private
         viewMode   : TViewMode;
         ScanCache  : TArray<TScanResult>;
         itemsMin   : Integer;
         itemsMax   : Integer;
         percent    : Integer;
         isScanning : Boolean;
         appExit    : Boolean;
         bkTask     : ITask;
         pbPercent  : TPercentProgressBar;
         procedure AutosizeListViewColumns(lv: TListView);
         procedure lvNetScanFilterItem(Sender: TObject; Item: TListItem; var IsVisible: Boolean);
         procedure lvNetScanCompare(Sender: TObject; Item1, Item2: TListItem; Data: Integer; var Compare: Integer);
         procedure SaveResultsToCache;
         procedure ApplyFilter;
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
         lv.Columns[i].Width:=-1; // autosize
   finally
      lv.Items.EndUpdate;
   end;
end;

procedure TfrmNetScan.lvNetScanFilterItem(Sender: TObject; Item: TListItem; var IsVisible: Boolean);
begin
   // By default, assume the item should be shown
   IsVisible:=True;

   case viewMode of
      vmAll:     IsVisible:=True;
      vmOnline:  IsVisible:=(Item.Caption = 'Online');
      vmOffline: IsVisible:=(Item.Caption = 'Offline') or (Item.Caption = 'Pending');
   end;
end;

procedure TfrmNetScan.lvNetScanCompare(Sender: TObject; Item1, Item2: TListItem; Data: Integer; var Compare: Integer);
begin
   // Instead of sorting alphabetically by Status text ('Online'/'Offline'),
   // we force it to keep chronological order based on the IP address string (SubItems[0])
   Compare:=CompareText(Item1.SubItems[0], Item2.SubItems[0]);
end;

procedure TfrmNetScan.SaveResultsToCache;
begin
   // Allocate memory space for the array matching our list item count
   SetLength(ScanCache, lvNetScan.Items.Count);

   for var i := 0 to lvNetScan.Items.Count - 1 do
   begin
      ScanCache[i].Status     := lvNetScan.Items[i].Caption;
      ScanCache[i].IP         := lvNetScan.Items[i].SubItems[0];
      ScanCache[i].HostName   := lvNetScan.Items[i].SubItems[1];
      ScanCache[i].MacAddr    := lvNetScan.Items[i].SubItems[2];
      ScanCache[i].ImageIndex := lvNetScan.Items[i].ImageIndex;
   end;
end;

procedure TfrmNetScan.ApplyFilter;
begin
   // Safety check: If the cache hasn't been built yet, don't clear the screen
   if Length(ScanCache) = 0 then Exit;

   lvNetScan.Items.BeginUpdate;
   try
      lvNetScan.Items.Clear;

      for var i := 0 to High(ScanCache) do
      begin
         var R := ScanCache[i];

         // Apply filter criteria
         case viewMode of
            vmOnline:  if R.Status <> 'Online' then Continue;
            vmOffline: if (R.Status <> 'Offline') and (R.Status <> 'Pending') then Continue;
            vmAll:     ; // Show everything
         end;

         var Item := lvNetScan.Items.Add;
         Item.Caption := R.Status;
         Item.SubItems.Add(R.IP);
         Item.SubItems.Add(R.HostName);
         Item.SubItems.Add(R.MacAddr);
         Item.ImageIndex := R.ImageIndex;
      end;
   finally
      lvNetScan.Items.EndUpdate;
   end;

   AutosizeListViewColumns(lvNetScan);
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
   Result:='Unknown';

   HostEnt:=GetHostByAddr(@TargetAddr, SizeOf(TargetAddr), AF_INET);
   if Assigned(HostEnt) then
      Result:=string(AnsiString(HostEnt^.h_name));
end;

//-------------------------------------------------------------------------------------------------
// GetMAC
function TfrmNetScan.GetMAC(TargetAddr: DWORD): string;
var
   macAddr: array[0..5] of Byte;
   macLen : DWORD;
begin
   Result:='Unknown';
   MacLen:=SizeOf(MacAddr);

   if SendARP(TargetAddr, 0, @macAddr[0], macLen) = 0 then
      Result:=Format('%.2x-%.2x-%.2x-%.2x-%.2x-%.2x', [MacAddr[0], MacAddr[1], MacAddr[2], MacAddr[3], MacAddr[4], MacAddr[5]])
end;


//-------------------------------------------------------------------------------------------------
// ScanRange
procedure TfrmNetScan.ScanRange(baseIP: String; minIP, maxIP: Integer);
begin
   itemsMin := minIP;
   itemsMax := maxIP;

   var localBaseIP := baseIP + '.';
   var totalIPs := (maxIP - minIP) + 1;

   isScanning:=True;
   appExit:=False;

   btnScan.Enabled:=False;
   mnuNetScan_View.Enabled:=False;
   cbView.Enabled:=True;

   pbPercent.Min := 0;
   pbPercent.Max := totalIPs;
   pbPercent.Position := 0;

   // 1. PRE-ALLOCATE THE DATA CACHE FIRST (The Threads' Safe Zone)
   SetLength(ScanCache, totalIPs);

   lvNetScan.Items.BeginUpdate;
   try
      lvNetScan.Items.Clear;
      for var i := itemsMin to itemsMax do
      begin
         var idx := i - itemsMin;

         // Set default values inside our stable memory cache
         ScanCache[idx].Status := 'Pending';
         ScanCache[idx].IP := localBaseIP + i.ToString;
         ScanCache[idx].HostName := '';
         ScanCache[idx].MacAddr := '';
         ScanCache[idx].ImageIndex := 1;

         // Populate UI initially
         var item := lvNetScan.Items.Add;
         item.Caption := ScanCache[idx].Status;
         item.SubItems.Add(ScanCache[idx].IP);
         item.SubItems.Add(ScanCache[idx].HostName);
         item.SubItems.Add(ScanCache[idx].MacAddr);
         item.ImageIndex := ScanCache[idx].ImageIndex;
      end;
   finally
      lvNetScan.Items.EndUpdate;
   end;
   AutosizeListViewColumns(lvNetScan);

   var CompletedCount := 0;

   bkTask := TTask.Run(Procedure
   begin
      TParallel.For(itemsMin, itemsMax, Procedure(index: Integer)
      var
         CurrentIP : String;
         IsOnline  : Boolean;
         TargetAddr: DWORD;
         HostName  : String;
         MacAddr   : String;
         CacheIdx  : Integer;
      begin
         if appExit then Exit;

         CacheIdx := index - itemsMin;
         CurrentIP := ScanCache[CacheIdx].IP;

         TargetAddr := IPToDWORD(CurrentIP);
         if TargetAddr = INADDR_NONE then Exit;
         IsOnline := PingIP(TargetAddr);

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

         // 2. WRITE DIRECTLY TO ARRAY MEMORY (Completely safe from visual UI clears!)
         ScanCache[CacheIdx].HostName := HostName;
         ScanCache[CacheIdx].MacAddr := MacAddr;
         if IsOnline then
         begin
            ScanCache[CacheIdx].Status := 'Online';
            ScanCache[CacheIdx].ImageIndex := 0;
         end
         else
         begin
            ScanCache[CacheIdx].Status := 'Offline';
            ScanCache[CacheIdx].ImageIndex := 1;
         end;

         var currentProgress := TInterlocked.Increment(CompletedCount);

         TThread.Queue(nil, procedure
         begin
            if appExit then Exit;

            pbPercent.Position := currentProgress;

            // Update live UI only if the item is still present on screen
            if (CacheIdx >= 0) and (CacheIdx < lvNetScan.Items.Count) then
            begin
               var Item:= lvNetScan.Items[CacheIdx];
               Item.SubItems[1]:=ScanCache[CacheIdx].HostName;
               Item.SubItems[2]:=ScanCache[CacheIdx].MacAddr;
               Item.Caption:=ScanCache[CacheIdx].Status;
               Item.ImageIndex:=ScanCache[CacheIdx].ImageIndex;
            end;
         end);
      end);

      // Cleanup block when entire scan completes
      TThread.Queue(nil, procedure
      begin
         isScanning:=False;
         if Not appExit then
         begin
            // 3. Process the filter choice cleanly onto the finished data set
            ApplyFilter;
            pbPercent.Position:=pbPercent.Max;

            mnuNetScan_View.Enabled:=False;
            cbView.Enabled:=True;
            btnScan.Enabled:=True;
         end;
      end);
   end);
end;

//-------------------------------------------------------------------------------------------------
// frmNetScan onCreate
procedure TfrmNetScan.FormCreate(Sender: TObject);
begin
   Self.Caption:=appCaption;
   viewMode:=vmAll;
   cbView.ItemIndex:=Ord(viewMode);

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

procedure TfrmNetScan.cbViewChange(Sender: TObject);
begin
   case cbView.ItemIndex of
      0: viewMode:=vmAll;
      1: viewMode:=vmOnline;
      2: viewMode:=vmOffline;
   end;

   mnuNetScan_View_All.Checked     := (viewMode = vmAll);
   mnuNetScan_View_Online.Checked  := (viewMode = vmOnline);
   mnuNetScan_View_Offline.Checked := (viewMode = vmOffline);

   ApplyFilter;
end;

procedure TfrmNetScan.mnuNetScan_View_AllClick(Sender: TObject);
begin
cbView.ItemIndex := 0;
   cbViewChange(cbView);
end;

procedure TfrmNetScan.mnuNetScan_View_OnlineClick(Sender: TObject);
begin
cbView.ItemIndex := 1;
   cbViewChange(cbView);
end;

procedure TfrmNetScan.mnuNetScan_View_OfflineClick(Sender: TObject);
begin
cbView.ItemIndex := 2;
   cbViewChange(cbView);
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

