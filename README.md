<img width="1200" height="630" alt="discord-tunneling-readme-banner" src="https://github.com/user-attachments/assets/7c14a907-2248-4476-bf39-d6f3b93d6d24" />


# Discord Single-Tunneling

Route only Discord's traffic through a WireGuard VPN, while the rest of your
system keeps using your normal internet connection. Built to work around
Discord's Go Live / camera restriction in regions where it's currently
disabled, without paying for a VPN provider's per-app split tunneling feature
and without slowing down the rest of your PC.

**Windows desktop only.** No admin rights, no virtual network adapter —
just a local proxy Discord's launch flag points at.

## What you need

- **Windows 10 or 11**
- **A WireGuard `.conf` file** from any VPN provider — Proton VPN, Mullvad,
  Windscribe and others all export these, and free tiers usually include it.
- **Discord desktop app** installed.

## Step 1 — Get your WireGuard config file

Log in to your VPN provider and download a **WireGuard configuration** file.
It's a small `.conf` text file.

- **Proton VPN:** [account.protonvpn.com/downloads](https://account.protonvpn.com/downloads)
  → *WireGuard configuration* → pick a server → **Download**.
- Other providers: look for "WireGuard", "Manual configuration" or
  "Config files" in your account dashboard.

Save it somewhere you can find it — your Downloads folder is fine.

> The file contains your private VPN key. Don't share it or commit it anywhere.

## Step 2 — Download the installer

Go to the [**Releases**](https://github.com/himingal/discord-tunneling/releases/latest)
page and download **`DiscordTunneling-Setup.exe`** from the latest release.

Windows SmartScreen may warn you about an unrecognized publisher, since the
installer isn't code-signed. Click **More info → Run anyway**, or build it
yourself from source (see below).

## Step 3 — Install

Run `DiscordTunneling-Setup.exe` and click through the wizard
(Next → Next → Finish). It installs the app and creates a shortcut with a
**pink gear icon**, named *Discord Single-Tunneling*.

Nothing is tunneled yet — the installer only puts the app in place.

## Step 4 — Import your VPN config

Open **Discord Single-Tunneling** (the gear icon).

1. Leave **"Start automatically when Windows starts"** checked, unless you'd
   rather start the tunnel by hand.
2. Click **Select VPN config file & Install** and pick the `.conf` file from
   Step 1.

The app downloads sing-box if it isn't already present, builds the
configuration, and starts the tunnel. When the status dot turns
**green — "Tunnel running"**, you're done.

## Step 5 — Use it

Click **Open Discord (Tunneling)**, or use the **"Discord (Tunneling)"**
shortcut it created on your Desktop. This launches a separate, tunneled
Discord instance — your regular Discord shortcut is untouched and still
uses your normal connection.

- You can **close the app window**; the tunnel keeps running in the background.
- With autostart enabled, the tunnel comes up on its own at every boot.
- Reopening the app when the tunnel is stopped shows a **Reconfigure**
  button — click it to start the tunnel again without re-importing your
  `.conf`.

To confirm it's working, check that your Go Live / camera options are
available in the tunneled Discord.

## How it works

[sing-box](https://github.com/SagerNet/sing-box) runs your WireGuard config
as a local **SOCKS5 proxy** on `127.0.0.1:1080`. The "Discord (Tunneling)"
shortcut launches Discord with `--proxy-server=socks5://127.0.0.1:1080`, so
only that Discord instance's traffic goes through the proxy — your normal
Discord shortcut, and everything else on the PC, keeps its regular route.

```
  Discord (Tunneling) shortcut          Everything else
  (--proxy-server flag)                 (normal Discord, browser, games...)
            |                                     |
            v                                     |
   sing-box SOCKS5 (127.0.0.1:1080)                |
            |                                     |
            v                                     v
     WireGuard -> your VPN provider        your normal connection
```

## What the installer does

- Downloads [sing-box](https://github.com/SagerNet/sing-box) if it isn't
  already present.
- Reads `PrivateKey`, `Address`, `PublicKey` and `Endpoint` from your `.conf` —
  no manual editing.
- Generates `config.json`: a WireGuard endpoint feeding a local SOCKS5
  listener.
- Creates the **Discord (Tunneling)** desktop shortcut with the proxy flag
  baked in.
- Optionally registers autostart via a Startup-folder shortcut, so the
  tunnel is already running by the time you log in.

## Troubleshooting

**The tunnel won't start**
Look at `sing-box.log` in the install folder. A common cause is the same
WireGuard `.conf` already being used somewhere else — a provider's WireGuard
session is single-use, so a phone or another PC signed in with the same
`.conf` will keep bouncing this one offline. Generate a fresh `.conf` if so.

**Voice, video or screen share isn't tunneled**
This version routes Discord through a SOCKS5 proxy, which only carries
TCP/HTTP(S) traffic. Chromium never sends WebRTC's UDP sockets through a
SOCKS5 proxy, so calls, video and screen share fall back to your normal
connection — only chat, login and API traffic are actually tunneled. This is
a limitation of the proxy approach itself, not a bug to report.

**Antivirus blocked something**
Auto-downloaded executables sometimes get flagged. If sing-box won't start,
check your AV logs first.

## Building from source

The repo includes an [Inno Setup](https://jrsoftware.org/isinfo.php) script if
you'd rather build the installer yourself:

1. Install Inno Setup.
2. Open `setup.iss` in the Inno Setup Compiler.
3. **Build → Compile** (Ctrl+F9).
4. Find `DiscordTunneling-Setup.exe` in the generated `output/` folder.

You can also skip the installer entirely and run `installer.ps1` directly
(right-click → Run with PowerShell). If you do, keep it in a folder you won't
move — the tunnel's config and autostart shortcut point at wherever you ran it
from.

## Known limitations

- **Voice, video and screen share are not tunneled** — see Troubleshooting
  above. Only chat, login and API traffic go through the VPN.
- **Windows only.** This is a desktop tool and doesn't cover phones.
- If you need every kind of Discord traffic tunneled, run Discord in a
  lightweight VM with the VPN applied to its whole network instead.

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
