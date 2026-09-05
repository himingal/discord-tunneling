<img width="1200" height="630" alt="discord-tunneling-readme-banner" src="https://github.com/user-attachments/assets/7c14a907-2248-4476-bf39-d6f3b93d6d24" />


# Discord Single-Tunneling

Route only Discord's traffic through a WireGuard VPN, while the rest of
your system keeps using your normal internet connection. Built to work
around Discord's Go Live / camera restriction in regions where it's
currently disabled, without paying for a VPN provider's per-app split
tunneling feature and without slowing down the rest of your PC.

## How it works

[sing-box](https://github.com/SagerNet/sing-box) creates a virtual network
adapter (TUN) backed by a WireGuard tunnel, and a routing rule matches
traffic **by process name** (`Discord.exe`/`Update.exe`) instead of relying
on Discord's `--proxy-server` launch flag. Everything Discord's process
sends — chat, login, and voice/video/screen share (WebRTC/UDP) — goes
through the VPN; every other process on your PC keeps using its normal
route.

```
        All system traffic (every process)
                    |
                    v
     sing-box TUN adapter (route by process name)
           |                          |
   Discord.exe / Update.exe   everything else
           |                          |
           v                          v
   WireGuard -> your VPN        direct (your normal
       provider                    connection)
```

This replaces an earlier SOCKS5-proxy-based design. A plain
`--proxy-server=socks5://…` flag only ever carries TCP/HTTP(S) traffic —
Chromium/Electron never routes WebRTC's UDP sockets through it — so voice,
video and screen share used to fall back to your normal connection
regardless of the flag. Routing by process name at the TUN/network layer
catches that traffic too.

## Requirements

- Windows 10/11
- Administrator rights — creating the TUN adapter and setting OS routes
  needs elevation, so the app now asks for a UAC prompt on launch
- Any VPN provider that can export a standard **WireGuard `.conf` file**
  (Proton VPN, Mullvad, Windscribe, etc. — even free tiers usually support this)
- Discord desktop app installed

## Quick start

1. Download your `.conf` file from your VPN provider's dashboard
   (look for "WireGuard configuration" under Downloads/Account).
2. Run `installer.ps1` (double-click, or right-click → Run with PowerShell).
   A small app window opens — no console/terminal is shown.
3. Check or uncheck "Start automatically when Windows starts".
4. Click **Select VPN config file & Install** and choose your `.conf` file.
5. Once it finishes, use the **"Discord (Tunneling)"** shortcut created on your
   desktop, or the **Open Discord (Tunneling)** button inside the app.

## Building the .exe installer (optional)

This repo includes an [Inno Setup](https://jrsoftware.org/isinfo.php)
script for anyone who wants a standard Windows installer experience
(Next > Next > Finish) instead of running the PowerShell script directly.

1. Install Inno Setup.
2. Open `setup.iss` in the Inno Setup Compiler.
3. Build → Compile (Ctrl+F9).
4. Find `DiscordTunneling-Setup.exe` in the generated `output/` folder.

## Interface

The app is a small native Windows GUI (built with .NET WinForms via
PowerShell) with a status indicator and a checkbox for autostart —
no PowerShell console window is shown at any point.

## What the installer does

- Relaunches itself elevated (one UAC prompt) — required to create the
  TUN adapter and set OS routes.
- Downloads the latest [sing-box](https://github.com/SagerNet/sing-box)
  release automatically if it's not already present.
- Downloads the [wintun](https://www.wintun.net/) driver (`wintun.dll`)
  that sing-box needs to create the virtual adapter on Windows.
- Parses the standard WireGuard fields (`PrivateKey`, `Address`,
  `PublicKey`, `Endpoint`) from your `.conf` file — no manual editing needed.
- Generates a `config.json` for sing-box: a TUN inbound, the WireGuard
  endpoint, and a route/DNS rule that matches `Discord.exe`/`Update.exe`
  by process name and sends only that traffic (TCP **and** UDP) to the
  VPN — everything else falls through to your normal connection.
- Creates a **"Discord (Tunneling)"** desktop shortcut (no launch flags
  needed anymore — matching happens by process name, so any Discord
  window is tunneled while the app is running).
- Verifies the machine is still online after starting the tunnel, and
  **automatically shuts the tunnel back down if it isn't**. Because the
  TUN adapter takes over the default route, a bad config can take the
  whole PC offline; rather than leaving you stranded with no connection
  to look up a fix with, the installer rolls back on its own.
- Optionally registers the tunnel to start on Windows boot, via a
  Scheduled Task set to run elevated at logon (a plain Startup-folder
  shortcut can't silently request the admin rights TUN needs). Autostart
  is only registered if the connectivity check above passed, so a broken
  config can never come back at every logon.

## Known limitations

- **Upgrading from an older SOCKS5-based install:** click
  **"Reconfigure"** once after updating. This regenerates `config.json`
  for the new TUN-based setup, refreshes the desktop shortcut (drops the
  old `--proxy-server` flag, which would otherwise point at a proxy that
  no longer exists), and replaces the old Startup-folder autostart entry
  with the new Scheduled Task.
- **Any Discord window is tunneled while the tunnel is running** — since
  matching happens by process name rather than by a launch flag, there's
  no longer a distinction between a "regular" and "tunneled" Discord
  instance on the same PC. Opening Discord from the Start Menu or the
  dedicated shortcut has the same effect once the tunnel is active.
- Antivirus/EDR software occasionally flags new TUN/WinTun adapters or
  auto-downloaded executables; if sing-box fails to start, check your
  AV logs first.

If you need guaranteed 100% tunneling for non-Discord traffic too (or
prefer not to grant admin rights), run Discord inside a lightweight VM
with the VPN configured for its entire network instead.

## Author

<table>
<tr>
<td><img width="72" height="72" alt="avatar" src="https://github.com/user-attachments/assets/e49fd325-aa4d-407b-9a84-8f225e6f4c68" /></td>
<td>

### mingal
Discord: `mingalmingalmingal`

</td>
</tr>
</table>

## License

MIT — see [LICENSE](LICENSE).
