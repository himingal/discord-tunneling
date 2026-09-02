<img src="./discord-tunneling-readme-banner.png" width="100%" alt="Discord Single-Tunneling" />

# Discord Single-Tunneling

Route only Discord's traffic through a WireGuard VPN, while the rest of
your system keeps using your normal internet connection. Built to work
around Discord's Go Live / camera restriction in regions where it's
currently disabled, without paying for a VPN provider's per-app split
tunneling feature and without slowing down the rest of your PC.

## How it works

Discord's desktop client (Electron/Chromium) accepts a `--proxy-server`
launch flag. This project spins up a local SOCKS5 proxy backed by a
WireGuard tunnel (via [sing-box](https://github.com/SagerNet/sing-box)),
and points a dedicated Discord shortcut at that proxy — nothing else on
your machine is affected.

```
Discord.exe --proxy-server=socks5://127.0.0.1:1080
                    |
                    v
        sing-box (SOCKS5 -> WireGuard)
                    |
                    v
              Your VPN provider
```

## Requirements

- Windows 10/11
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

- Downloads the latest [sing-box](https://github.com/SagerNet/sing-box)
  release automatically if it's not already present.
- Parses the standard WireGuard fields (`PrivateKey`, `Address`,
  `PublicKey`, `Endpoint`) from your `.conf` file — no manual editing needed.
- Generates a `config.json` for sing-box (SOCKS5 inbound on
  `127.0.0.1:1080`, routed through the WireGuard endpoint).
- Creates a **"Discord (Tunneling)"** shortcut with the proxy flag.
- Optionally registers the tunnel to start on Windows boot.

## Known limitation

Some Discord voice/video media servers run on general-purpose cloud
providers (not a dedicated ASN), and Chromium doesn't route WebRTC
media traffic through `--proxy-server` by default. In practice this
means chat, login and API calls reliably go through the tunnel; some
voice/video sessions may not. If you need a guaranteed 100% tunnel,
run Discord inside a lightweight VM with the VPN configured for its
entire network instead.

## Author

<table>
<tr>
<td><img src="./avatar.png" width="72" height="72" alt="mingal" /></td>
<td>

### mingal
Discord: `mingalmingalmingal`

</td>
</tr>
</table>

## License

MIT — see [LICENSE](LICENSE).
