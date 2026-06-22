//-------------------------------------------------------------------------------------------------
// IPHlpAPI.dll
//    © 2026 Remus Rigo
//       v1.0 2026-05-17
//-------------------------------------------------------------------------------------------------

unit iphlpapi_dll;

interface //---------------------------------------------------------------------------------------

uses
  Winapi.Windows;

type
   IP_OPTION_INFORMATION = record
      TTL:         Byte;
      Tos:         Byte;
      Flags:       Byte;
      OptionsSize: Byte;
      OptionsData: Pointer;
   end;

   ICMP_ECHO_REPLY = record
      Address:       DWORD;
      Status:        DWORD;
      RoundTripTime: DWORD;
      DataSize:      Word;
      Reserved:      Word;
      Data:          Pointer;
      Options:       IP_OPTION_INFORMATION;
   end;

function IcmpCreateFile: THandle; stdcall;

function IcmpCloseHandle(IcmpHandle: THandle): BOOL; stdcall;

function IcmpSendEcho(
   IcmpHandle: THandle;
   DestinationAddress: DWORD;
   RequestData: Pointer;
   RequestSize: Word;
   RequestOptions: Pointer;
   ReplyBuffer: Pointer;
   ReplySize: DWORD;
   Timeout: DWORD
): DWORD; stdcall;

function SendARP(DestIP: DWORD; SrcIP: DWORD; pMacAddr: Pointer; var PhyAddrLen: DWORD): DWORD; stdcall;

implementation //----------------------------------------------------------------------------------

function IcmpCreateFile: THandle; stdcall; external 'iphlpapi.dll' name 'IcmpCreateFile';

function IcmpCloseHandle(IcmpHandle: THandle): BOOL; stdcall; external 'iphlpapi.dll' name 'IcmpCloseHandle';

function IcmpSendEcho(
   IcmpHandle: THandle;
   DestinationAddress: DWORD;
   RequestData: Pointer;
   RequestSize: Word;
   RequestOptions: Pointer;
   ReplyBuffer: Pointer;
   ReplySize: DWORD;
   Timeout: DWORD
): DWORD; stdcall; external 'iphlpapi.dll' name 'IcmpSendEcho';

function SendARP; external 'iphlpapi.dll' name 'SendARP';

end.
