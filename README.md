<img width="1200" height="630" alt="discord-tunneling-readme-banner" src="https://github.com/user-attachments/assets/7c14a907-2248-4476-bf39-d6f3b93d6d24" />

# Discord Single-Tunneling

![Platform](https://img.shields.io/badge/platform-Windows-0078D6?logo=windows&logoColor=white)
![Language](https://img.shields.io/badge/language-PowerShell-5391FE?logo=powershell&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-3DA639)

Route only Discord's traffic through a WireGuard VPN, while the rest of your
system keeps using your normal internet connection. Built to work around
Discord's Go Live / camera restriction in regions where it's currently
disabled, without paying for a VPN provider's per-app split tunneling feature
and without slowing down the rest of your PC.

**Voice, video and screen share included — not just chat.**

**Windows desktop only.**

## Why

A VPN client routes everything — every browser tab, every download, every
other game — through a server that's further away than your ISP. Turn it on
to unblock Discord's camera and the rest of the PC pays for it in latency.
Turn it off and Discord goes back to being restricted.

This tool exists so that trade-off doesn't have to be made. It watches for
one thing — Discord's own processes — and only those get the VPN. Everything
else on the machine never even notices it's running.

```
Without split tunneling:              With Discord Single-Tunneling:

  VPN ON                                Discord.exe / Update.exe
    |                                            |
    v                                            v
  everything slow,                          WireGuard -> VPN
  Discord unblocked                              |
                                        everything else, full speed
  VPN OFF                                        |
    |                                    Discord unblocked too
    v
  everything fast,
  Discord restricted
```

## What it does

🔌 Reads any standard WireGuard `.conf` file — works with Proton, Mullvad, or whatever VPN you already have
🎙️ **Voice, video and screen share included** — not just chat, login and API
🧠 Auto-downloads and configures [sing-box](https://github.com/SagerNet/sing-box) and the wintun driver, no manual setup
🖥️ Clean native GUI — no terminal, no console window, ever
🚀 Just open Discord — no special shortcut, no launch flags
🛟 **Rolls back on its own** if the tunnel ever breaks your connection, instead of leaving you stranded
🔁 Follows your adapter — swap Ethernet for Wi-Fi and it keeps working, no reconfiguring
⚙️ Optional autostart with Windows, hardened against the network not being ready yet at logon

## What you need

- **Windows 10 or 11**
- **Administrator rights.** The tunnel creates a virtual network adapter, which
  Windows only allows with elevation. You'll get one UAC prompt.
- **A WireGuard `.conf` file** from any VPN provider — Proton VPN, Mullvad,
  Windscribe and others all export these, and free tiers usually include it.
- **Discord desktop app** installed.

## Installing it

### Step 1 — Get your WireGuard config file

Log in to your VPN provider and download a **WireGuard configuration** file.
It's a small `.conf` text file.

- **Proton VPN:** [account.protonvpn.com/downloads](https://account.protonvpn.com/downloads)
  → *WireGuard configuration* → pick a server → **Download**.
- Other providers: look for "WireGuard", "Manual configuration" or
  "Config files" in your account dashboard.

Save it somewhere you can find it — your Downloads folder is fine.

> The file contains your private VPN key. Don't share it or commit it anywhere
> (this repo's `.gitignore` already blocks that).

### Step 2 — Download the installer

Go to the [**Releases**](https://github.com/himingal/discord-tunneling/releases/latest)
page and download **`DiscordTunneling-Setup.exe`** from the latest release.

Windows SmartScreen may warn you about an unrecognized publisher, since the
installer isn't code-signed. Click **More info → Run anyway**, or build it
yourself from source (see below).

### Step 3 — Install

Run `DiscordTunneling-Setup.exe` and click through the wizard
(Next → Next → Finish). It installs the app and creates a shortcut with a
**pink gear icon**, named *Discord Single-Tunneling*.

Nothing is tunneled yet — the installer only puts the app in place.

### Step 4 — Import your VPN config

Open **Discord Single-Tunneling** (the gear icon).

1. **Accept the UAC prompt.** The app needs Administrator rights to create the
   tunnel adapter, so it asks once every time it starts.
2. Leave **"Start automatically when Windows starts"** checked, unless you'd
   rather start the tunnel by hand.
3. Click **Select VPN config file & Install** and pick the `.conf` file from
   Step 1.

The app then downloads sing-box and the wintun driver, builds the
configuration, starts the tunnel, and **checks that your PC is still online**.
If anything went wrong it shuts the tunnel back down by itself and tells you —
your connection is never left broken.

When the status dot turns **green — "Tunnel running"**, you're done.

### Step 5 — Use it

Just open Discord. Any Discord window is routed through the VPN while the
tunnel is running — the desktop shortcut, the Start Menu, the tray icon, all
the same.

- You can **close the app window**; the tunnel keeps running in the background.
- With autostart enabled, the tunnel comes up on its own at every boot.
- Reopening the app when the tunnel is stopped **starts it again
  automatically** — you don't need to re-import your `.conf`.

To confirm it's working, open Discord and try joining someone's screen share,
or check that your Go Live / camera options are available.

## How it works

[sing-box](https://github.com/SagerNet/sing-box) creates a virtual network
adapter (TUN) backed by your WireGuard tunnel, and a routing rule matches
traffic **by process name** (`Discord.exe` / `Update.exe`). Everything
Discord's process sends — chat, login, and voice/video/screen share
(WebRTC/UDP) — goes through the VPN; every other process keeps its normal
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

Earlier versions used Discord's `--proxy-server` launch flag pointed at a local
SOCKS5 proxy. That flag only ever carries TCP/HTTP(S) traffic — Chromium never
routes WebRTC's UDP sockets through it — so voice, video and screen share
silently fell back to the normal connection. Starting your own stream usually
worked; joining someone else's didn't. Matching by process name at the network
layer catches that traffic too.

## What the installer does

- Relaunches itself elevated (one UAC prompt), required for the TUN adapter.
- Downloads [sing-box](https://github.com/SagerNet/sing-box) and the
  [wintun](https://www.wintun.net/) driver if they aren't already present, and
  replaces a sing-box binary that's too old for the config it generates.
- Reads `PrivateKey`, `Address`, `PublicKey` and `Endpoint` from your `.conf` —
  no manual editing.
- Generates `config.json`: a TUN inbound, the WireGuard endpoint, and
  route/DNS rules matching Discord by process name. IPv6 is only enabled when
  your provider actually gave you an IPv6 address.
- Creates the **Discord (Tunneling)** desktop shortcut.
- Verifies the PC is still online afterwards and **rolls the tunnel back
  automatically** if it isn't — the TUN takes over the default route, so a bad
  config could otherwise take the whole machine offline.
- Registers autostart as a Scheduled Task that runs elevated and windowless at
  logon, waits for a real network connection before dialing the VPN (not just
  a route table entry), and supervises the first 20 seconds — restarting the
  tunnel if the log shows a dead-endpoint dial instead of leaving a zombie
  tunnel running all day. Autostart is only registered once the connectivity
  check passes, so a broken config can't come back at every boot.

## How it is put together

```
installer.ps1     the whole app — GUI, .conf parsing, config.json generation,
                   tunnel lifecycle (start/stop/rollback), autostart, the
                   embedded logon-time launcher script
setup.iss          Inno Setup script — packages installer.ps1 + assets into
                   DiscordTunneling-Setup.exe
assets/            icons (app + gear) and the banner/avatar artwork
sing-box.exe       downloaded automatically on first run, not shipped
config.json        generated from your .conf on install, gitignored (holds
                   your private key)
```

There's no build step beyond Inno Setup — `installer.ps1` is plain Windows
PowerShell + WinForms, run directly or wrapped into an installer.

## Troubleshooting

**Discord hangs on "Starting…"**
Almost always a leftover shortcut from v1.x still passing
`--proxy-server=socks5://127.0.0.1:1080`, a proxy that no longer exists.
Open the app and click **Reconfigure** once; it rewrites the desktop and
Startup shortcuts.

**The tunnel won't stay up**
Look at `sing-box.log` in the install folder — that's the first place to check
when the tunnel starts but traffic doesn't flow. Errors are logged at `warn`
level, so a healthy tunnel leaves it nearly empty.

**My whole PC lost internet**
It shouldn't — the app checks and rolls back on its own. If a tunnel is somehow
left running, end `sing-box.exe` in Task Manager and your connection returns
immediately.

**I switched from Ethernet to Wi-Fi**
Nothing to do. The adapter is re-detected every time the tunnel starts.

**Antivirus (especially a company-managed one) blocks it**
A self-elevating app that creates a virtual network adapter looks exactly like
what endpoint security is built to catch — that's not a false positive to
work around. On a managed work PC, use the tool on a personal machine instead
rather than requesting an exception.

## Building from source

The repo includes an [Inno Setup](https://jrsoftware.org/isinfo.php) script if
you'd rather build the installer yourself:

1. Install Inno Setup.
2. Open `setup.iss` in the Inno Setup Compiler.
3. **Build → Compile** (Ctrl+F9).
4. Find `DiscordTunneling-Setup.exe` in the generated `output/` folder.

You can also skip the installer entirely and run `installer.ps1` directly
(right-click → Run with PowerShell). If you do, keep it in a folder you won't
move — the tunnel's config and autostart task point at wherever you ran it
from, and having a second copy elsewhere leads to two installs fighting over
the same tunnel.

## Known limitations

- **Any Discord window is tunneled while the tunnel runs.** Matching is by
  process name, not by a launch flag, so there's no separate "untunneled"
  Discord on the same PC.
- **Windows only.** This is a desktop tool and doesn't cover phones.
- **Managed/corporate antivirus will likely block it** — see Troubleshooting.
- If you need guaranteed 100% tunneling for non-Discord traffic too, or would
  rather not grant admin rights, run Discord in a lightweight VM with the VPN
  applied to its whole network instead.

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
