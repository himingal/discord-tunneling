<img width="1200" height="630" alt="discord-tunneling-readme-banner" src="https://github.com/user-attachments/assets/7c14a907-2248-4476-bf39-d6f3b93d6d24" />


# Discord Single-Tunneling

Route only Discord's traffic through a WireGuard VPN, while the rest of your
system keeps using your normal internet connection. Built to work around
Discord's Go Live / camera restriction in regions where it's currently
disabled, without paying for a VPN provider's per-app split tunneling feature
and without slowing down the rest of your PC.

Voice, video and screen share included — not just chat.

## What you need

- **Windows 10 or 11**
- **Administrator rights.** The tunnel creates a virtual network adapter, which
  Windows only allows with elevation. You'll get one UAC prompt.
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

## Step 5 — Use it

Just open Discord. Any Discord window is routed through the VPN while the
tunnel is running — the desktop shortcut, the Start Menu, the tray icon, all
the same.

- You can **close the app window**; the tunnel keeps running in the background.
- With autostart enabled, the tunnel comes up on its own at every boot, and
  Discord waits for it before opening.
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
  logon, plus a small waiter that holds Discord until the tunnel is up. This is
  only registered once the connectivity check passes, so a broken config can't
  come back at every boot.

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

**Antivirus blocked something**
New TUN adapters and auto-downloaded executables sometimes get flagged. If
sing-box won't start, check your AV logs first.

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
- **iOS isn't possible.** Android is — see below.
- If you need guaranteed 100% tunneling for non-Discord traffic too, or would
  rather not grant admin rights, run Discord in a lightweight VM with the VPN
  applied to its whole network instead.

## Android

Your phone gets the same split tunnel, from the same `.conf` — and there's
nothing to configure once it's imported.

Click **"On Android too? Get the config for your phone"** in the desktop app and
pick the phone's own `.conf`. It writes
**`discord-tunneling-android.json`**: a complete sing-box profile with Discord
already set as the only app routed through the tunnel. Scan a QR on the PC and
the phone gets it over your own Wi-Fi — no file to copy, and nothing to
configure after importing.

> The profile contains your VPN private key, same as the desktop config. The
> handoff below keeps it on your local network; if you move the file around by
> hand instead, treat it like a password.

### Why there's no APK

There isn't one, and adding one wouldn't help. Android sandboxing stops any app
from writing into sing-box's private storage, so an "installer app" would have
to *be* a VPN client — a fork of sing-box carrying your keys, unsigned and
outside Play Store review. sing-box already registers a
`sing-box://import-remote-profile` URL scheme, which is why a tap on a local
web page does the same job with software you can verify.

> **Your phone needs a second `.conf`, not the PC's.** WireGuard identifies a
> peer by its key and the VPN server keeps one session per key, so two devices
> sharing a config make the server hand the session back and forth between
> them — Discord looks connected but calls won't go through. Proton VPN lets
> you create several configs from the same free account; download another one
> for the phone. The app checks and refuses the PC's config if you pick it by
> mistake.

### Step 1 — Install sing-box on the phone

Get **sing-box** from
[Google Play](https://play.google.com/store/apps/details?id=io.nekohasekai.sfa)
or [F-Droid](https://f-droid.org/en/packages/io.nekohasekai.sfa/).

### Step 2 — Scan the QR from inside sing-box

In the desktop app, click **"On Android too? Get the config for your phone"**.
A QR code appears.

On the phone — same Wi-Fi as the PC — open **sing-box**, go to **New profile**
and tap the **scan** icon, then point it at the QR. The profile fills itself
in; save it.

Scan it from inside sing-box, not with the system camera. The QR holds a
`sing-box://` import link, and scanning is the one route that hands it over
intact — released builds reject a plain URL in the scanner, and a browser tap
on the same link is unreliable.

While that window is open, the PC serves the profile on your local network and
opens a firewall rule for it, both scoped to the local subnet and both closed
again when you shut the window. Nothing is uploaded anywhere.

**If neither the QR nor the address works**, click **"Neither works? Save the
file to send yourself"** in that same window. That route uses no network at
all: send `discord-tunneling-android.json` to your phone by cable, cloud or
message, then in sing-box choose **New profile → Type: Local → Import from
file**. It always works.

### Step 3 — Turn it on

In sing-box, go to **Dashboard**, select the profile, and tap the toggle.
Android asks once to allow the VPN connection — accept it.

That's it. Discord goes through the VPN; every other app on the phone keeps its
normal connection.

### If the phone can't reach the PC

The app opens the firewall for its own port while the handoff window is up, but
some networks isolate wireless clients from each other, and a phone on mobile
data or a guest SSID isn't on your LAN at all. Use the file route in that case —
the button in the same window — since it needs no network.

### Notes

- **Don't touch the per-app proxy screen in sing-box's settings.** The app's UI
  setting *overrides* what's in the config file, so leaving it alone is what
  keeps `include_package` in charge.
- **The profile is imported as a Remote one**, so sing-box remembers the PC's
  address. The configuration itself is already downloaded and keeps working
  after the PC's handoff stops — but leave auto-update off, or the profile will
  periodically try to reach a PC that isn't serving anything.
- Only `com.discord` is routed. To add another build — a beta, a fork — add its
  package name to `include_package` in the JSON and re-import.
- No root needed. Android's `VpnService` does per-app routing natively, which
  is why the phone side is far simpler than the Windows side.

## What about iOS?

Not possible in any honest form. Per-app VPN on iOS exists only for devices
managed through an MDM; a consumer app can't route a single app's traffic. The
closest approximation is routing by destination rather than by app — sending
only Discord's IP ranges through the tunnel, which sing-box for iOS can
express — but it's a rough match and breaks whenever Discord changes
infrastructure.

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
