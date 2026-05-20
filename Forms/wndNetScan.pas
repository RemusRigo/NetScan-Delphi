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
   System.SysUtils, System.Variants, System.Classes, System.Threading, System.SyncObjs, System.Generics.Collections,
   Vcl.Graphics, Vcl.Controls, Vcl.ComCtrls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Forms, Vcl.Dialogs,
   System.ImageList, Vcl.ImgList, Vcl.Menus, Vcl.ToolWin,
   WinSock, StrUtils,
   PercentProgressBar;

type
   TScanResult = record
      Status    : string;
      IP        : string;
      HostName  : string;
      macAddr   : string;
      ImageIndex: Integer;
   end;

   TParsedRange = record
      BaseIP: string;
      MinIP : Integer;
      MaxIP : Integer;
      Total : Integer;
   end;

   TfrmNetScan = class(TForm)
      mnuNetScan             : TMainMenu;
      popMnuListView         : TPopupMenu;
      imgListStatus          : TImageList;
      mnuNetScan_File        : TMenuItem;
      mnuNetScan_File_Exit   : TMenuItem;
      mnuNetScan_About       : TMenuItem;
      ToolBar: TToolBar;
    toolBtnScan: TToolButton;
      edIP: TEdit;
      lvNetScan: TListView;
      ToolButton2: TToolButton;
    StatusBar: TStatusBar;
      procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
      procedure FormCreate(Sender: TObject);
      procedure btnScanClick(Sender: TObject);
      procedure mnuNetScan_AboutClick(Sender: TObject);
      procedure toolBtnScanClick(Sender: TObject);
    procedure ToolButton2Click(Sender: TObject);
      private
         ScanCache  : TArray<TScanResult>;
         itemsMin   : Integer;
         itemsMax   : Integer;
         percent    : Integer;
         isScanning : Boolean;
         viewOffline: Boolean;
         appExit    : Boolean;
         bkTask     : ITask;
         pbPercent  : TPercentProgressBar;
         procedure AutosizeListViewColumns(lv: TListView);
         function  IPToDWORD(const IP: string): DWORD;
         function  PingIP(TargetAddr: DWORD): Boolean;
         function  GetHostName(TargetAddr: DWORD): string;
         function  GetHostNameWSA(TargetAddr: DWORD): string;
         function  GetMAC(TargetAddr: DWORD): string;
         function  ParseRangeStr(const RangeStr: string; out RangeResult: TParsedRange): Boolean;
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

//-------------------------------------------------------------------------------------------------
// IPToDWORD
function TfrmNetScan.IPToDWORD(const IP: string): DWORD;
begin
   Result:=inet_addr(PAnsiChar(AnsiString(IP)));
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
// GetHostName
function TfrmNetScan.GetHostName(TargetAddr: DWORD): string;
var
   hostEnt: PHostEnt;
   WSAData: TWSAData;
begin
   Result:='Unknown';
   hostEnt:=GetHostByAddr(@TargetAddr, SizeOf(TargetAddr), AF_INET);
   if Assigned(hostEnt) then
      Result:=string(AnsiString(hostEnt^.h_name));
end;

//-------------------------------------------------------------------------------------------------
// GetHostNameWSA (Windows Sockets API)
function TfrmNetScan.GetHostNameWSA(TargetAddr: DWORD): string;
var
   hostEnt: PHostEnt;
   WSAData: TWSAData;
begin
   Result:='Unknown';

   if WSAStartup(MAKEWORD(2, 2), WSAData) <> 0 then
      Exit;

   try
      if TargetAddr <> INADDR_NONE then
      begin
         // Perform reverse DNS lookup (equivalent to Dns.GetHostEntry)
         hostEnt:=gethostbyaddr(@TargetAddr, SizeOf(TargetAddr), AF_INET);
         if Assigned(hostEnt) then
            Result := string(AnsiString(hostEnt^.h_name))
         else
           Result:='Unknown (Error: ' + IntToStr(WSAGetLastError) + ')';
      end
      else
         Result := 'Unknown (Invalid IP address)';
   finally
      WSACleanup;
   end;
end;

//-------------------------------------------------------------------------------------------------
// GetMAC
function TfrmNetScan.GetMAC(TargetAddr: DWORD): string;
var
   macAddr: array[0..5] of Byte;
   macLen : DWORD;
begin
   Result:='Unknown';
   macLen:=SizeOf(MacAddr);

   if SendARP(TargetAddr, 0, @macAddr[0], macLen) = 0 then
      Result:=Format('%.2x-%.2x-%.2x-%.2x-%.2x-%.2x', [MacAddr[0], MacAddr[1], MacAddr[2], MacAddr[3], MacAddr[4], MacAddr[5]])
end;

//-------------------------------------------------------------------------------------------------
// ParseRange
function TfrmNetScan.ParseRangeStr(const RangeStr: string; out RangeResult: TParsedRange): Boolean;
begin
   Result := False;

   var DashIdx := RangeStr.IndexOf('-');
   if DashIdx = -1 then Exit;

   var MaxStr := RangeStr.Substring(DashIdx + 1);
   var LeftStr := RangeStr.Substring(0, DashIdx);

   var LastDotIdx := LeftStr.LastIndexOf('.');
   if LastDotIdx = -1 then Exit;

   RangeResult.BaseIP := LeftStr.Substring(0, LastDotIdx);
   var MinStr     := LeftStr.Substring(LastDotIdx + 1);

   RangeResult.MinIP  := StrToIntDef(MinStr, -1);
   RangeResult.MaxIP  := StrToIntDef(MaxStr, -1);

   if (RangeResult.MinIP <> -1) and (RangeResult.MaxIP <> -1) and (RangeResult.MinIP <= RangeResult.MaxIP) then
   begin
      RangeResult.Total := (RangeResult.MaxIP - RangeResult.MinIP) + 1;
      Result := True;
   end;
end;

//-------------------------------------------------------------------------------------------------
// ScanRange
procedure TfrmNetScan.ScanRange(baseIP: String; minIP, maxIP: Integer);
begin
   itemsMin:=minIP;
   itemsMax:=maxIP;

   var localBaseIP:=baseIP + '.';
   var totalIPs:=(maxIP - minIP) + 1;

   isScanning:=True;
   appExit:=False;

   pbPercent.Min:=0;
   pbPercent.Max:=totalIPs;
   pbPercent.Position:= 0;

   lvNetScan.Items.Clear;

   var CompletedCount := 0;

   bkTask:=TTask.Run(Procedure
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

         CacheIdx:=index - itemsMin;
         CurrentIP:=localBaseIP + index.ToString;
         TargetAddr:=IPToDWORD(CurrentIP);

         if TargetAddr = INADDR_NONE then Exit;

         IsOnline:=PingIP(TargetAddr);

         if appExit then Exit;

         TThread.Queue(nil, procedure
         begin
            if IsOnline then
            begin
               HostName:=GetHostName(TargetAddr);
               MacAddr:=GetMAC(TargetAddr);

               if appExit then Exit;

               var item:=lvNetScan.Items.Add;
               item.Caption:='Online';
               item.SubItems.Add(CurrentIP);
               item.SubItems.Add(HostName);
               item.SubItems.Add(MacAddr);
               item.ImageIndex := 0;
            end;
            StatusBar.SimpleText:=CurrentIP;
         end);

         var currentProgress:=TInterlocked.Increment(CompletedCount);
         pbPercent.Position:=currentProgress;

         // Cleanup block when entire scan completes
         TThread.Queue(nil, procedure
         begin
            isScanning:=False;
            if not appExit then
            begin
               pbPercent.Position:=pbPercent.Max;
               AutosizeListViewColumns(lvNetScan);
//               StatusBar.SimpleText:='Scan complete';
            end;
         end);
      end);
   end);
end;

//-------------------------------------------------------------------------------------------------
// toolBtnScan OnClick
procedure TfrmNetScan.toolBtnScanClick(Sender: TObject);
var
   parsedRange : TParsedRange;
begin
   if not ParseRangeStr(edIP.Text, parsedRange) then
   begin
      ShowMessage('Invalid range');
      Exit;
   end
   else
      ScanRange(parsedRange.BaseIP,parsedRange.MinIP,parsedRange.MaxIP);
end;

procedure TfrmNetScan.ToolButton2Click(Sender: TObject);
begin

end;

//-------------------------------------------------------------------------------------------------
// frmNetScan onCreate
procedure TfrmNetScan.FormCreate(Sender: TObject);
begin
   Self.Caption:=appCaption;
 //  viewOffline:=True;

   // initialize PercentProgressBar
   pbPercent:=TPercentProgressBar.Create(Self);
   pbPercent.Parent:=frmNetScan;
   pbPercent.Left:=3;
   pbPercent.Height:=18;
   pbPercent.Top:=Self.ClientHeight-pbPercent.Height-StatusBar.Height-3;
   pbPercent.Width:=Self.ClientWidth-6;
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

//-------------------------------------------------------------------------------------------------
// btnScan onClick
procedure TfrmNetScan.btnScanClick(Sender: TObject);
var
   parsedRange : TParsedRange;
begin
   if not ParseRangeStr(edIP.Text, parsedRange) then
   begin
      ShowMessage('Invalid range');
      Exit;
   end
   else
      ScanRange(parsedRange.BaseIP,parsedRange.MinIP,parsedRange.MaxIP);
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

