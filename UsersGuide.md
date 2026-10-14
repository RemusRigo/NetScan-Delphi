# NetScan: User's Guide

> This is the Delphi version, **on hold**. The [VB.NET version](https://github.com/RemusRigo/NetScan-VB.NET)
> has more features (multiple ranges, vendor, TTL/OS, presets, pause/stop).



## Downloads & Runtimes

Download the latest release from the [Releases page](https://github.com/RemusRigo/NetScan-Delphi/releases).

|Folder|Architecture|Required Runtime|
|-|-|-|
|`Win32`|32-bit|none (native Windows app)|
|`Win64`|64-bit|none (native Windows app)|

> On 64-bit Windows, use **Win64**.



## Install

NetScan is portable: there is no installer. Copy `NetScan.exe` to a folder and double-click it.

> If Windows blocks the file ("Windows protected your PC"), right-click `NetScan.exe` →
> **Properties** → check **Unblock** → **OK**, then try again.



## Usage

1. The IP range box is filled with your local network, e.g. `192.168.1.1-255`.
   Edit it if needed: `first-three-octets.from-to` (only the last octet can be a range).
2. Click **Scan**. The progress bar shows how far the scan is.

Only the devices that answer the ping are listed:

|Column|Description|
|-|-|
|**Status**|Online|
|**IP**|The IP address|
|**Hostname**|Name returned by DNS|
|**MAC**|Found with ARP; only for devices on your local subnet|

> Devices that block ping (for example, by a firewall) are not listed.

**File → About** for version information, **File → Exit** to close NetScan.



## Uninstall

Delete `NetScan.exe`. NetScan doesn't write any settings.
