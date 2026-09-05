# ============================================================
#  Discord Tunneling
#  made by mingal
#
#  Routes only Discord's traffic through a WireGuard VPN,
#  leaving the rest of the system on the normal connection.
# ============================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# TUN mode needs to create a virtual network adapter and set OS routes,
# which requires an elevated (Administrator) process on Windows.
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($env:DT_HIDDEN -ne "1" -or -not $isAdmin) {
    $env:DT_HIDDEN = "1"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.UseShellExecute = $true
    if (-not $isAdmin) { $psi.Verb = "runas" }
    try {
        [System.Diagnostics.Process]::Start($psi) | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Discord Tunneling needs Administrator rights to create its virtual network adapter (TUN), which is what lets it route Discord's voice/video/screen share (UDP) traffic, not just chat.`n`nPlease reopen and accept the UAC prompt.", "Administrator rights required", "OK", "Warning") | Out-Null
    }
    exit
}

$base = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $base) { $base = (Get-Location).Path }
Set-Location $base

# ---------- Brand palette ----------
$BrandPink   = [System.Drawing.Color]::FromArgb(246, 87, 169)
$BrandPinkDk = [System.Drawing.Color]::FromArgb(214, 60, 140)
$LogGreen    = [System.Drawing.Color]::FromArgb(43, 168, 110)
$LogYellow   = [System.Drawing.Color]::FromArgb(200, 140, 20)
$LogRed      = [System.Drawing.Color]::FromArgb(210, 60, 60)
$LogGray     = [System.Drawing.Color]::FromArgb(120, 120, 125)
$InfoBoxBg   = [System.Drawing.Color]::FromArgb(252, 235, 244)
$InfoBoxText = [System.Drawing.Color]::FromArgb(150, 45, 100)

# Gear for this window and the app's own shortcut; the plain logo (app.ico)
# stays on the "Discord (Tunneling)" launcher so the two are told apart.
$iconPath = Join-Path $base "assets\app_settings.ico"
$logoPngPath = Join-Path $base "assets\app_logo.png"
$avatarPath = Join-Path $base "assets\avatar.png"
$appIcon = $null
if (Test-Path $iconPath) { $appIcon = New-Object System.Drawing.Icon($iconPath) }

# ---------- Helper: rounded rectangle region (for a modern look) ----------
function Set-RoundedRegion($control, $radius) {
    $w = $control.Width
    $h = $control.Height
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $radius * 2
    $path.AddArc(0, 0, $d, $d, 180, 90)
    $path.AddArc($w - $d, 0, $d, $d, 270, 90)
    $path.AddArc($w - $d, $h - $d, $d, $d, 0, 90)
    $path.AddArc(0, $h - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $control.Region = New-Object System.Drawing.Region($path)
}

function Get-CircularImage($sourcePath, $diameter) {
    $src = [System.Drawing.Image]::FromFile($sourcePath)
    $bmp = New-Object System.Drawing.Bitmap($diameter, $diameter)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddEllipse(0, 0, $diameter, $diameter)
    $g.SetClip($path)
    $g.DrawImage($src, 0, 0, $diameter, $diameter)
    $g.Dispose()
    return $bmp
}

# ============================================================
#  Helper functions (core logic)
# ============================================================

function Get-DownloadsFolder {
    $downloads = Join-Path $env:USERPROFILE "Downloads"
    if (Test-Path $downloads) { return $downloads }
    return $env:USERPROFILE
}

function Get-Field($pattern, $content) {
    $m = [regex]::Match($content, $pattern)
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return $null
}

function Test-TunnelInstalled {
    return (Test-Path (Join-Path $base "sing-box.exe")) -and (Test-Path (Join-Path $base "config.json")) -and (Test-Path (Join-Path $base "wintun.dll"))
}

function Test-TunnelRunning {
    return $null -ne (Get-Process -Name "sing-box" -ErrorAction SilentlyContinue)
}

# ============================================================
#  Main form
# ============================================================

$form = New-Object System.Windows.Forms.Form
$form.Text = "Discord Tunneling"
$form.ClientSize = New-Object System.Drawing.Size(440, 462)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::White
if ($appIcon) { $form.Icon = $appIcon }

# ---------- Header ----------
$header = New-Object System.Windows.Forms.Panel
$header.Size = New-Object System.Drawing.Size(440, 86)
$header.Location = New-Object System.Drawing.Point(0, 0)
$header.BackColor = $BrandPink
$form.Controls.Add($header)

$header.Add_Paint({
    param($sender, $e)
    $rect = New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $sender.Height)
    $gradBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $BrandPink, $BrandPinkDk, 35)
    $e.Graphics.FillRectangle($gradBrush, $rect)
    $gradBrush.Dispose()
})

if (Test-Path $logoPngPath) {
    $logoBox = New-Object System.Windows.Forms.PictureBox
    $logoBox.Image = [System.Drawing.Image]::FromFile($logoPngPath)
    $logoBox.SizeMode = "Zoom"
    $logoBox.Size = New-Object System.Drawing.Size(50, 50)
    $logoBox.Location = New-Object System.Drawing.Point(20, 18)
    $logoBox.BackColor = [System.Drawing.Color]::Transparent
    $header.Controls.Add($logoBox)
}

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "Discord Tunneling"
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [System.Drawing.Color]::White
$titleLabel.AutoSize = $true
$titleLabel.BackColor = [System.Drawing.Color]::Transparent
$titleLabel.Location = New-Object System.Drawing.Point(84, 16)
$header.Controls.Add($titleLabel)

$taglineLabel = New-Object System.Windows.Forms.Label
$taglineLabel.Text = "Encrypted routing for Discord only"
$taglineLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$taglineLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 226, 241)
$taglineLabel.AutoSize = $true
$taglineLabel.BackColor = [System.Drawing.Color]::Transparent
$taglineLabel.Location = New-Object System.Drawing.Point(86, 50)
$header.Controls.Add($taglineLabel)

# ---------- Status row ----------
$statusDot = New-Object System.Windows.Forms.Label
$statusDot.Text = [char]0x25CF
$statusDot.Font = New-Object System.Drawing.Font("Segoe UI", 12)
$statusDot.ForeColor = [System.Drawing.Color]::Gray
$statusDot.Location = New-Object System.Drawing.Point(22, 102)
$statusDot.Size = New-Object System.Drawing.Size(20, 20)
$form.Controls.Add($statusDot)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Tunnel not installed yet"
$statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10.5)
$statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
$statusLabel.AutoSize = $true
$statusLabel.Location = New-Object System.Drawing.Point(42, 102)
$form.Controls.Add($statusLabel)

# ---------- Info box (rounded, taller) ----------
$infoBox = New-Object System.Windows.Forms.Panel
$infoBox.Location = New-Object System.Drawing.Point(20, 132)
$infoBox.Size = New-Object System.Drawing.Size(400, 108)
$infoBox.BackColor = $InfoBoxBg
$form.Controls.Add($infoBox)
Set-RoundedRegion $infoBox 12

$infoLabel = New-Object System.Windows.Forms.Label
$infoLabel.Text = "You can close this window - the tunnel keeps running in the background." + "`n`n" + "Routes all of Discord's traffic (including voice/video/screen share) through your VPN via a virtual adapter, while the rest of your PC keeps its normal connection. Needs one Administrator (UAC) prompt."
$infoLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8.7)
$infoLabel.ForeColor = $InfoBoxText
$infoLabel.Location = New-Object System.Drawing.Point(14, 8)
$infoLabel.Size = New-Object System.Drawing.Size(374, 92)
$infoBox.Controls.Add($infoLabel)

# ---------- Autostart checkbox ----------
$autostartCheck = New-Object System.Windows.Forms.CheckBox
$autostartCheck.Text = "Start automatically when Windows starts"
$autostartCheck.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$autostartCheck.Checked = $true
$autostartCheck.AutoSize = $true
$autostartCheck.Location = New-Object System.Drawing.Point(22, 252)
$form.Controls.Add($autostartCheck)

# ---------- Main action button (rounded) ----------
$installButton = New-Object System.Windows.Forms.Button
$installButton.Text = "Select VPN config file && Install"
$installButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$installButton.ForeColor = [System.Drawing.Color]::White
$installButton.BackColor = $BrandPink
$installButton.FlatStyle = "Flat"
$installButton.FlatAppearance.BorderSize = 0
$installButton.Size = New-Object System.Drawing.Size(400, 42)
$installButton.Location = New-Object System.Drawing.Point(20, 286)
$installButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($installButton)
Set-RoundedRegion $installButton 10

# ---------- Get a config file link ----------
$getConfLink = New-Object System.Windows.Forms.LinkLabel
$getConfLink.Text = "Don't have a .conf file yet? Get one from Proton VPN"
$getConfLink.Font = New-Object System.Drawing.Font("Segoe UI", 8.3)
$getConfLink.LinkColor = $BrandPinkDk
$getConfLink.AutoSize = $false
$getConfLink.TextAlign = "MiddleCenter"
$getConfLink.Size = New-Object System.Drawing.Size(400, 18)
$getConfLink.Location = New-Object System.Drawing.Point(20, 330)
$form.Controls.Add($getConfLink)
$getConfLink.Add_Click({
    Start-Process "https://account.protonvpn.com/downloads"
})

# ---------- Open Discord button (rounded, outline) ----------
$openButton = New-Object System.Windows.Forms.Button
$openButton.Text = "Open Discord (Tunneling)"
$openButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$openButton.ForeColor = $BrandPinkDk
$openButton.BackColor = [System.Drawing.Color]::FromArgb(253, 244, 249)
$openButton.FlatStyle = "Flat"
$openButton.FlatAppearance.BorderSize = 0
$openButton.Size = New-Object System.Drawing.Size(400, 38)
$openButton.Location = New-Object System.Drawing.Point(20, 354)
$openButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$openButton.Enabled = $false
$form.Controls.Add($openButton)
Set-RoundedRegion $openButton 10

function Set-Progress($text, [System.Drawing.Color]$color = $LogGray) {
    # Silent - errors still surface via MessageBox; no idle status text shown.
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}

# ---------- Divider + credit row (avatar + made by mingal, bottom) ----------
$divider = New-Object System.Windows.Forms.Panel
$divider.Size = New-Object System.Drawing.Size(400, 1)
$divider.Location = New-Object System.Drawing.Point(20, 398)
$divider.BackColor = [System.Drawing.Color]::FromArgb(235, 235, 238)
$form.Controls.Add($divider)

$creditPill = New-Object System.Windows.Forms.Panel
$creditPill.Size = New-Object System.Drawing.Size(168, 34)
$creditPill.Location = New-Object System.Drawing.Point(136, 412)
$creditPill.BackColor = [System.Drawing.Color]::FromArgb(250, 248, 250)
$form.Controls.Add($creditPill)
Set-RoundedRegion $creditPill 17

$creditPanel = New-Object System.Windows.Forms.Panel
$creditPanel.Size = New-Object System.Drawing.Size(148, 24)
$creditPanel.Location = New-Object System.Drawing.Point(10, 5)
$creditPanel.BackColor = [System.Drawing.Color]::Transparent
$creditPill.Controls.Add($creditPanel)

if (Test-Path $avatarPath) {
    $avatarBox = New-Object System.Windows.Forms.PictureBox
    $avatarBox.Image = Get-CircularImage $avatarPath 24
    $avatarBox.SizeMode = "Zoom"
    $avatarBox.Size = New-Object System.Drawing.Size(24, 24)
    $avatarBox.Location = New-Object System.Drawing.Point(0, 0)
    $avatarBox.BackColor = [System.Drawing.Color]::Transparent
    $creditPanel.Controls.Add($avatarBox)
}

$creditLabel = New-Object System.Windows.Forms.Label
$creditLabel.Text = "made by mingal"
$creditLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$creditLabel.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 145)
$creditLabel.AutoSize = $true
$creditLabel.Location = New-Object System.Drawing.Point(30, 5)
$creditPanel.Controls.Add($creditLabel)




# ============================================================
#  Core actions
# ============================================================

function Set-Status($text, [System.Drawing.Color]$color) {
    $statusLabel.Text = $text
    $statusDot.ForeColor = $color
}

# Config uses schema that landed in 1.12 (rule actions, endpoints,
# default_domain_resolver). An older binary left over from a previous install
# loads it wrong or not at all, so a stale sing-box.exe gets replaced.
$singboxMinimumVersion = [version]"1.12.0"

function Get-SingBoxVersion($exePath) {
    try {
        $output = & $exePath version 2>&1 | Select-Object -First 1
        $m = [regex]::Match([string]$output, '(\d+)\.(\d+)\.(\d+)')
        if ($m.Success) { return [version]$m.Value }
    } catch { }
    return $null
}

function Ensure-SingBox {
    $singboxExe = Join-Path $base "sing-box.exe"
    if (Test-Path $singboxExe) {
        $installed = Get-SingBoxVersion $singboxExe
        if ($installed -and $installed -ge $singboxMinimumVersion) {
            Set-Progress "sing-box already present." $LogGreen
            return $true
        }
        Set-Progress "sing-box is outdated - updating..." $LogYellow
        Remove-Item $singboxExe -Force -ErrorAction SilentlyContinue
        if (Test-Path $singboxExe) {
            [System.Windows.Forms.MessageBox]::Show("An old sing-box.exe is in use and can't be replaced. Stop the tunnel (end sing-box.exe in Task Manager) and click Install again.", "Update blocked", "OK", "Warning") | Out-Null
            return $false
        }
    }
    Set-Progress "Downloading sing-box..." $LogGray
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/SagerNet/sing-box/releases/latest"
        $asset = $release.assets | Where-Object { $_.name -match "windows-amd64\.zip$" } | Select-Object -First 1
        if (-not $asset) { throw "No windows-amd64 asset found in latest release." }

        $zipPath = Join-Path $base "singbox_temp.zip"
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath
        $extractPath = Join-Path $base "singbox_temp_extract"
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

        $exeFound = Get-ChildItem -Path $extractPath -Recurse -Filter "sing-box.exe" | Select-Object -First 1
        Copy-Item $exeFound.FullName -Destination $singboxExe -Force

        Remove-Item $zipPath -Force
        Remove-Item $extractPath -Recurse -Force
        Set-Progress "sing-box downloaded." $LogGreen
        return $true
    } catch {
        Set-Progress "Failed to download sing-box." $LogRed
        [System.Windows.Forms.MessageBox]::Show("Could not auto-download sing-box.`n`nDownload it manually from github.com/SagerNet/sing-box/releases, place sing-box.exe in this folder, and click Install again.`n`nDetails: $($_.Exception.Message)", "Download failed", "OK", "Error") | Out-Null
        return $false
    }
}

function Ensure-Wintun {
    $wintunDll = Join-Path $base "wintun.dll"
    if (Test-Path $wintunDll) {
        Set-Progress "wintun.dll already present." $LogGreen
        return $true
    }
    Set-Progress "Downloading wintun driver..." $LogGray
    try {
        $zipPath = Join-Path $base "wintun_temp.zip"
        Invoke-WebRequest -Uri "https://www.wintun.net/builds/wintun-0.14.1.zip" -OutFile $zipPath
        $extractPath = Join-Path $base "wintun_temp_extract"
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

        $dllFound = Get-ChildItem -Path $extractPath -Recurse -Filter "wintun.dll" | Where-Object { $_.FullName -match "\\amd64\\" } | Select-Object -First 1
        if (-not $dllFound) { $dllFound = Get-ChildItem -Path $extractPath -Recurse -Filter "wintun.dll" | Select-Object -First 1 }
        Copy-Item $dllFound.FullName -Destination $wintunDll -Force

        Remove-Item $zipPath -Force
        Remove-Item $extractPath -Recurse -Force
        Set-Progress "wintun driver downloaded." $LogGreen
        return $true
    } catch {
        Set-Progress "Failed to download wintun." $LogRed
        [System.Windows.Forms.MessageBox]::Show("Could not auto-download the wintun driver (needed for the TUN adapter that carries Discord's voice/video traffic).`n`nDownload it manually from wintun.net, copy the amd64\wintun.dll into this folder, and click Install again.`n`nDetails: $($_.Exception.Message)", "Download failed", "OK", "Error") | Out-Null
        return $false
    }
}

function Build-ConfigFromConf($confPath) {
    Set-Progress "Reading your VPN config..." $LogGray
    $confContent = Get-Content -Path $confPath -Raw

    $privateKey = Get-Field 'PrivateKey\s*=\s*([^\r\n]+)' $confContent
    $addressRaw = Get-Field 'Address\s*=\s*([^\r\n]+)' $confContent
    $publicKey  = Get-Field 'PublicKey\s*=\s*([^\r\n]+)' $confContent
    $endpoint   = Get-Field 'Endpoint\s*=\s*([^\r\n]+)' $confContent

    if (-not $privateKey -or -not $addressRaw -or -not $publicKey -or -not $endpoint) {
        Set-Progress "Could not read the .conf file." $LogRed
        [System.Windows.Forms.MessageBox]::Show("Could not parse all required fields from the .conf file. Please check it's a valid WireGuard config export.", "Parse error", "OK", "Error") | Out-Null
        return $false
    }

    # Support exactly the address families the VPN actually handed us. Claiming
    # more than that is what made Discord hang: the peer's allowed_ips used to
    # advertise ::/0 unconditionally, so Discord's IPv6 connections were routed
    # into a tunnel with no IPv6 address to send them from, and every one of
    # them died with "missing IPv6 local address" while Discord kept retrying.
    $addressParts = ($addressRaw -split ",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    $addressIPv4 = $addressParts | Where-Object { $_ -notmatch ':' } | Select-Object -First 1
    $addressIPv6 = $addressParts | Where-Object { $_ -match ':' } | Select-Object -First 1

    $endpointAddresses = @()
    $allowedIps = @()
    $tunAddresses = @("172.19.0.1/30")
    $tunRouteAddresses = @("0.0.0.0/0")
    if ($addressIPv4) {
        $endpointAddresses += $addressIPv4
        $allowedIps += "0.0.0.0/0"
    }
    if ($addressIPv6) {
        $endpointAddresses += $addressIPv6
        $allowedIps += "::/0"
        $tunAddresses += "fdfe:dcba:9876::1/126"
        $tunRouteAddresses += "::/0"
    }
    # Without a v6 address the TUN must not capture v6 at all - traffic it
    # swallows but can't forward is worse than traffic it never touches.
    $dnsStrategy = if ($addressIPv6) { "prefer_ipv4" } else { "ipv4_only" }

    $endpointParts = $endpoint -split ":"
    $endpointHost = $endpointParts[0]
    $endpointPort = $endpointParts[1]

    # If the VPN server is a literal IP, exclude it from the TUN's captured
    # routes too, as a second line of defense alongside the interface
    # detection below.
    $routeExcludeAddresses = @()
    if ($endpointHost -match '^\d{1,3}(\.\d{1,3}){3}$') {
        $routeExcludeAddresses += "$endpointHost/32"
    }

    # Discord's own process names, matched at the network layer so voice,
    # video and screen share (which are all UDP/WebRTC) get tunneled too -
    # a plain SOCKS5 proxy only ever carries the TCP/HTTP(S) traffic.
    $discordProcesses = @("Discord.exe", "Update.exe")

    # auto_route on the TUN makes it the OS's default route for everything, so
    # the "direct" outbound (which carries all non-Discord traffic) must
    # explicitly escape back out through the real adapter, or every non-Discord
    # connection on the whole PC loops into the TUN with nowhere to go - that
    # took down all networking, DNS included, during testing.
    #
    # auto_detect_interface rather than a fixed bind_interface: the adapter is
    # followed as it changes, so moving between Ethernet and Wi-Fi needs no
    # reconfiguring. domain_resolver is what makes this combination legal -
    # sing-box refuses a detour into an outbound carrying no explicit dial
    # fields ("detour to an empty direct outbound makes no sense"), and a
    # route-level auto_detect_interface doesn't count as one.
    $directOutbound = [ordered]@{ type = "direct"; tag = "direct"; domain_resolver = "dns-direct" }
    $wireguardEndpoint = [ordered]@{
        type = "wireguard"
        tag = "vpn"
        system = $false
        address = $endpointAddresses
        private_key = $privateKey
        mtu = 1408
        # Detours through "direct" instead of dialing for itself: a WireGuard
        # endpoint bound to an interface fails on Windows whenever that adapter
        # has IPv6 disabled, and the failed udp6 bind blocks the handshake
        # outright (SagerNet/sing-box#2900). Going through "direct" keeps the
        # endpoint away from that code path entirely.
        detour = "direct"
        peers = @(
            [ordered]@{
                address = $endpointHost
                port = [int]$endpointPort
                public_key = $publicKey
                allowed_ips = $allowedIps
                persistent_keepalive_interval = 25
            }
        )
    }
    $routeBlock = [ordered]@{
        auto_detect_interface = $true
        default_domain_resolver = "dns-direct"
        rules = @(
            [ordered]@{ process_name = $discordProcesses; action = "route"; outbound = "vpn" }
        )
        final = "direct"
    }

    $configObj = [ordered]@{
        # The tunnel runs hidden, so without this every failure is invisible -
        # the app can only report "it didn't work". sing-box.log is where to
        # look first when the tunnel starts but traffic doesn't flow.
        # "warn", never "info": at info level sing-box logs a line per
        # connection, and the TUN sees every connection the machine makes.
        # That produced a 3 GB log file in a few hours of ordinary use.
        log = [ordered]@{
            level = "warn"
            output = "sing-box.log"
            timestamp = $true
        }
        dns = [ordered]@{
            servers = @(
                # NOT "local": with auto_route on, a "local" server hands the
                # query to the OS resolver, whose reply packet gets captured
                # by the TUN again and re-resolved forever - a known sing-box
                # DNS loop (SagerNet/sing-box#3637). An explicit resolver with
                # its own detour skips the OS resolver entirely.
                [ordered]@{ type = "udp"; tag = "dns-direct"; server = "1.1.1.1"; server_port = 53; detour = "direct" }
                [ordered]@{ type = "udp"; tag = "dns-vpn"; server = "1.1.1.1"; server_port = 53; detour = "vpn" }
            )
            rules = @(
                [ordered]@{ process_name = $discordProcesses; action = "route"; server = "dns-vpn" }
            )
            # ipv4_only on an IPv4-only tunnel: handing back AAAA records the
            # tunnel can't reach just makes apps hang on dead connections.
            strategy = $dnsStrategy
            final = "dns-direct"
        }
        endpoints = @($wireguardEndpoint)
        inbounds = @(
            [ordered]@{
                type = "tun"
                tag = "tun-in"
                address = $tunAddresses
                mtu = 1400
                auto_route = $true
                route_address = $tunRouteAddresses
                # Deliberately false: strict_route exists to force *everything*
                # through the tunnel and block anything that escapes it, which
                # is the opposite of a split tunnel - here the traffic that
                # bypasses the TUN is the whole point. On Windows it also
                # interferes with multihomed DNS resolution and is documented
                # to break some applications.
                strict_route = $false
                stack = "system"
                route_exclude_address = $routeExcludeAddresses
            }
        )
        outbounds = @($directOutbound)
        route = $routeBlock
    }

    $configPath = Join-Path $base "config.json"
    $jsonText = $configObj | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($configPath, $jsonText, (New-Object System.Text.UTF8Encoding($false)))
    Set-Progress "Config file created." $LogGreen
    return $true
}

function New-DiscordShortcut {
    $WScriptShell = New-Object -ComObject WScript.Shell
    $discordUpdate = Join-Path $env:LOCALAPPDATA "Discord\Update.exe"
    if (-not (Test-Path $discordUpdate)) {
        Set-Progress "Discord not found on this PC." $LogYellow
        return $null
    }
    $desktop = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktop "Discord (Tunneling).lnk"
    $shortcut = $WScriptShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $discordUpdate
    # No --proxy-server flag needed anymore: the tunnel now matches Discord.exe
    # by process name at the network layer (see Build-ConfigFromConf), so any
    # Discord instance is routed through the VPN while the tunnel is running.
    $shortcut.Arguments = '--processStart Discord.exe'
    $shortcut.WorkingDirectory = Join-Path $env:LOCALAPPDATA "Discord"
    $customIcon = Join-Path $base "assets\app.ico"
    if (Test-Path $customIcon) { $shortcut.IconLocation = $customIcon } else { $shortcut.IconLocation = $discordUpdate }
    $shortcut.Save()
    Set-Progress "Desktop shortcut created." $LogGreen
    return $shortcutPath
}

$autostartTaskName = "DiscordTunneling"

function Remove-LegacyAutostart {
    # Cleans up the old (pre-TUN) SOCKS5-based autostart mechanism, which
    # launched sing-box non-elevated and would silently fail to create a
    # TUN adapter if left in place alongside the new scheduled task.
    $startupFolder = [Environment]::GetFolderPath("Startup")
    $startupShortcut = Join-Path $startupFolder "sing-box-vpn.lnk"
    if (Test-Path $startupShortcut) { Remove-Item $startupShortcut -Force }
    $vbsPath = Join-Path $base "iniciar.vbs"
    if (Test-Path $vbsPath) { Remove-Item $vbsPath -Force }
}

function Set-Autostart($enable) {
    Remove-LegacyAutostart
    Unregister-ScheduledTask -TaskName $autostartTaskName -Confirm:$false -ErrorAction SilentlyContinue

    if ($enable) {
        # TUN needs Administrator rights, so autostart uses a scheduled task
        # registered to run elevated at logon instead of a plain Startup
        # shortcut (which Windows cannot silently elevate).
        $action = New-ScheduledTaskAction -Execute (Join-Path $base "sing-box.exe") -Argument "run -c config.json" -WorkingDirectory $base

        # 20s delay: interface detection and the WireGuard handshake both need
        # a network that's actually up, which it often isn't at logon.
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $trigger.Delay = "PT20S"

        # ExecutionTimeLimit must be explicitly unlimited - the default kills
        # the task after 3 days, which would silently drop the tunnel on any
        # machine that stays up that long.
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) `
            -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

        # S4U rather than Interactive: an interactive task runs sing-box in the
        # user's session, which pops a console window on every logon. It looks
        # broken, and closing that window kills the tunnel. S4U runs it in the
        # background with no window and still elevates via RunLevel Highest.
        $userId = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $registered = $false
        try {
            $principal = New-ScheduledTaskPrincipal -UserId $userId -RunLevel Highest -LogonType S4U
            Register-ScheduledTask -TaskName $autostartTaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
            $registered = $true
        } catch {
            $registered = $false
        }
        if (-not $registered) {
            # S4U needs the "Log on as a batch job" right, which not every
            # account has. A visible console beats no autostart at all.
            $principal = New-ScheduledTaskPrincipal -UserId $userId -RunLevel Highest -LogonType Interactive
            Register-ScheduledTask -TaskName $autostartTaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        }
    }
}

function Stop-Tunnel {
    Get-Process -Name "sing-box" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

function Reset-OversizedLog {
    # sing-box appends forever and has no rotation of its own. At warn level the
    # log stays tiny, but an older install logging at info level filled 3 GB in
    # an afternoon - so a runaway log gets dropped while the tunnel is stopped
    # (the only moment the file isn't locked). Small logs are kept: they're the
    # evidence for whatever went wrong last run.
    $logPath = Join-Path $base "sing-box.log"
    if (-not (Test-Path $logPath)) { return }
    if ((Get-Item $logPath).Length -gt 20MB) {
        Remove-Item $logPath -Force -ErrorAction SilentlyContinue
    }
}

function Wait-ForTunAdapter($timeoutSeconds = 40) {
    # Opening the TUN adapter can take a long while on Windows - sing-box logs
    # "open interface take too much time to finish!" when it does - and routes
    # are in flux until it settles. Probing connectivity during that window
    # reads as a dead tunnel and rolls back one that was merely starting slowly.
    $deadline = (Get-Date).AddSeconds($timeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-TunnelRunning)) { return $false }
        $adapter = Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object { $_.InterfaceDescription -like "*Wintun*" -and $_.Status -eq "Up" }
        if ($adapter) {
            # Up, but the routing table needs a beat to catch up
            Start-Sleep -Seconds 3
            return $true
        }
        Start-Sleep -Milliseconds 750
        [System.Windows.Forms.Application]::DoEvents()
    }
    return (Test-TunnelRunning)
}

function Test-ConnectivityOk {
    # Verifies the machine can still reach the internet while the tunnel is up.
    # Both halves matter and fail differently:
    #  - the raw TCP connect proves non-Discord packets still escape the TUN
    #    and reach the physical adapter (a broken "direct" outbound hangs here)
    #  - the DNS lookup proves name resolution isn't looping back into the TUN
    #    (the classic auto_route + "local" resolver deadlock)
    $tcpOk = $false
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $async = $client.BeginConnect("1.1.1.1", 443, $null, $null)
        $tcpOk = $async.AsyncWaitHandle.WaitOne(4000, $false) -and $client.Connected
        $client.Close()
    } catch {
        $tcpOk = $false
    }
    if (-not $tcpOk) { return $false }

    $dnsOk = $false
    try {
        [System.Net.Dns]::GetHostEntry("cloudflare.com") | Out-Null
        $dnsOk = $true
    } catch {
        $dnsOk = $false
    }
    return $dnsOk
}

function Restart-Tunnel {
    # Always used after (re)writing config.json - a sing-box process already
    # running keeps using whatever config it loaded at launch, so a stale
    # process left over from a previous install/provider would silently keep
    # the old TUN/routing setup instead of the one just generated.
    Stop-Tunnel
    Reset-OversizedLog
    return (Start-Tunnel)
}

function Start-Tunnel {
    if (Test-TunnelRunning) {
        Set-Status "Tunnel running" $LogGreen
        return $true
    }
    $singboxExe = Join-Path $base "sing-box.exe"
    Start-Process -FilePath $singboxExe -ArgumentList "run -c config.json" -WorkingDirectory $base -WindowStyle Hidden
    Start-Sleep -Seconds 2

    if (-not (Test-TunnelRunning)) {
        Set-Progress "Tunnel failed to start." $LogRed
        Set-Status "Tunnel failed to start" $LogRed
        return $false
    }

    # The TUN takes over the machine's default route, so a bad config doesn't
    # just fail - it can take the whole PC offline. Verify the machine is still
    # reachable and roll the tunnel back automatically if it isn't, instead of
    # leaving someone stranded without a connection to go look up a fix with.
    #
    # Patience matters more than speed here: a false positive tears down a
    # working tunnel, which is exactly what an impatient check did on a machine
    # where the adapter took its time to open.
    Set-Progress "Waiting for the tunnel adapter..." $LogGray
    Wait-ForTunAdapter | Out-Null

    Set-Progress "Verifying connectivity..." $LogGray
    $ok = $false
    foreach ($attempt in 1..6) {
        if (Test-ConnectivityOk) { $ok = $true; break }
        if (-not (Test-TunnelRunning)) { break }
        Start-Sleep -Seconds 3
        [System.Windows.Forms.Application]::DoEvents()
    }

    if (-not $ok) {
        Stop-Tunnel
        Set-Progress "Tunnel rolled back." $LogRed
        Set-Status "Tunnel broke connectivity - rolled back" $LogRed
        [System.Windows.Forms.MessageBox]::Show("The tunnel started but the PC lost internet access, so it was shut down automatically and your connection has been restored.`n`nNothing is left running and autostart was not enabled, so a reboot won't bring this back.`n`nThis usually means sing-box couldn't route non-Discord traffic back out through your normal adapter. Please report this along with your Windows version and network setup.", "Tunnel rolled back", "OK", "Warning") | Out-Null
        return $false
    }

    Set-Progress "Tunnel started." $LogGreen
    Set-Status "Tunnel running" $LogGreen
    return $true
}

# ============================================================
#  Button events
# ============================================================

$installButton.Add_Click({
    $installButton.Enabled = $false

    if (-not (Ensure-SingBox)) { $installButton.Enabled = $true; return }
    if (-not (Ensure-Wintun)) { $installButton.Enabled = $true; return }

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Select your VPN WireGuard .conf file"
    $dialog.Filter = "WireGuard config (*.conf)|*.conf|All files (*.*)|*.*"
    $dialog.InitialDirectory = Get-DownloadsFolder

    if ($dialog.ShowDialog() -ne "OK") {
        Set-Progress "Cancelled." $LogYellow
        $installButton.Enabled = $true
        return
    }

    if (-not (Build-ConfigFromConf $dialog.FileName)) { $installButton.Enabled = $true; return }

    New-DiscordShortcut | Out-Null

    # Autostart is only registered once the tunnel has proven it keeps the
    # machine online - otherwise a bad config would come back at every logon,
    # with no working connection to fix it from.
    $tunnelOk = Restart-Tunnel
    Set-Autostart ($autostartCheck.Checked -and $tunnelOk)

    $openButton.Enabled = $tunnelOk
    $installButton.Text = "Reconfigure (select a different .conf)"
    $installButton.Enabled = $true
})

$openButton.Add_Click({
    $discordUpdate = Join-Path $env:LOCALAPPDATA "Discord\Update.exe"
    if (Test-Path $discordUpdate) {
        # Close any already-running Discord first: its existing connections were
        # opened before the tunnel's routes existed, so it needs a fresh start
        # to pick up the new (tunneled) route.
        $existingDiscord = Get-Process -Name "Discord" -ErrorAction SilentlyContinue
        if ($existingDiscord) {
            $existingDiscord | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 800
        }

        Start-Process -FilePath $discordUpdate -ArgumentList '--processStart Discord.exe'

        [System.Windows.Forms.MessageBox]::Show(
            "Discord (Tunneling) is launching!`n`nYou don't need to keep this window open - the tunnel keeps running quietly in the background even after you close it.`n`nThanks for using Discord Tunneling!",
            "All set",
            "OK",
            "Information"
        ) | Out-Null

        $form.Close()
    }
})

# ---------- Initial state on load ----------
if (Test-TunnelInstalled) {
    if (Test-TunnelRunning) {
        Set-Status "Tunnel running" $LogGreen
    } else {
        Set-Status "Tunnel installed, not running" $LogYellow
    }
    $openButton.Enabled = $true
    $installButton.Text = "Reconfigure (select a different .conf)"
} else {
    Set-Progress "Ready." $LogGray
}

[System.Windows.Forms.Application]::Run($form)
