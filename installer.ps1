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

function Get-PhysicalInterfaceAlias {
    # The adapter carrying the default route, skipping sing-box's own TUN.
    # That exclusion is the whole point: once auto_route is in place the TUN
    # *is* the default route, so anything that just reads the routing table -
    # sing-box's own route.auto_detect_interface included - picks the tunnel
    # and binds the direct outbound to it, which sing-box then rejects as a
    # "loopback connection to TUN range" and kills every UDP flow, DNS first.
    try {
        $routes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop | Sort-Object -Property RouteMetric
        foreach ($r in $routes) {
            $adapter = Get-NetAdapter -InterfaceIndex $r.InterfaceIndex -ErrorAction SilentlyContinue
            if ($adapter -and $adapter.Status -eq "Up" -and
                $adapter.Name -notlike "tun*" -and
                $adapter.InterfaceDescription -notlike "*sing-tun*") {
                return $adapter.Name
            }
        }
    } catch { }
    return $null
}

function Test-TunnelRunning {
    return $null -ne (Get-Process -Name "sing-box" -ErrorAction SilentlyContinue)
}

# ============================================================
#  Main form
# ============================================================

$form = New-Object System.Windows.Forms.Form
$form.Text = "Discord Tunneling"
$form.ClientSize = New-Object System.Drawing.Size(440, 486)
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

function Show-PhoneHandoffDialog($url) {
    # The QR carries the profile URL itself, scanned from inside sing-box.
    # Its scanner accepts a bare http(s) URL as a remote profile directly,
    # which is a shorter and better-understood path than the
    # sing-box://import-remote-profile scheme - that one goes through a
    # browser, and Chrome's handling of custom schemes is inconsistent enough
    # that tapping the link can fail outright.
    $profileUrl = "$url/profile.json"
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Send to your phone"
    $dlg.ClientSize = New-Object System.Drawing.Size(360, 470)
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.StartPosition = "CenterParent"
    $dlg.BackColor = [System.Drawing.Color]::White
    if ($appIcon) { $dlg.Icon = $appIcon }

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "Scan this from inside sing-box"
    $title.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = $BrandPinkDk
    $title.TextAlign = "MiddleCenter"
    $title.Size = New-Object System.Drawing.Size(340, 24)
    $title.Location = New-Object System.Drawing.Point(10, 12)
    $dlg.Controls.Add($title)

    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Text = "sing-box app  ->  New profile  ->  scan icon"
    $subtitle.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $subtitle.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 130)
    $subtitle.TextAlign = "MiddleCenter"
    $subtitle.Size = New-Object System.Drawing.Size(340, 18)
    $subtitle.Location = New-Object System.Drawing.Point(10, 34)
    $dlg.Controls.Add($subtitle)

    $qr = New-QrBitmap $profileUrl 7 3
    if ($qr) {
        $pic = New-Object System.Windows.Forms.PictureBox
        $pic.Image = $qr
        $pic.SizeMode = "Zoom"
        $pic.Size = New-Object System.Drawing.Size(280, 280)
        $pic.Location = New-Object System.Drawing.Point(40, 50)
        $dlg.Controls.Add($pic)
    }

    $urlBox = New-Object System.Windows.Forms.TextBox
    $urlBox.Text = $profileUrl
    $urlBox.ReadOnly = $true
    $urlBox.TextAlign = "Center"
    $urlBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $urlBox.BorderStyle = "FixedSingle"
    $urlBox.Size = New-Object System.Drawing.Size(300, 24)
    $urlBox.Location = New-Object System.Drawing.Point(30, 342)
    $dlg.Controls.Add($urlBox)

    $help = New-Object System.Windows.Forms.Label
    $help.Text = "Can't scan? In sing-box choose New profile, set Type to Remote, and paste that address as the URL." + "`r`n`r`n" +
                 "Either way, Discord is already the only app routed through it - nothing to set up afterwards." + "`r`n`r`n" +
                 "Both devices must be on the same Wi-Fi. Nothing leaves your network, and this stops working when you close this window."
    $help.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $help.ForeColor = [System.Drawing.Color]::FromArgb(95, 95, 105)
    $help.TextAlign = "TopCenter"
    $help.Size = New-Object System.Drawing.Size(320, 92)
    $help.Location = New-Object System.Drawing.Point(20, 372)
    $dlg.Controls.Add($help)

    $dlg.ShowDialog() | Out-Null
    if ($qr) { $qr.Dispose() }
    $dlg.Dispose()
}

# ---------- Android config link ----------
$androidLink = New-Object System.Windows.Forms.LinkLabel
$androidLink.Text = "On Android too? Get the config for your phone"
$androidLink.Font = New-Object System.Drawing.Font("Segoe UI", 8.3)
$androidLink.LinkColor = $BrandPinkDk
$androidLink.AutoSize = $false
$androidLink.TextAlign = "MiddleCenter"
$androidLink.Size = New-Object System.Drawing.Size(400, 18)
$androidLink.Location = New-Object System.Drawing.Point(20, 398)
$form.Controls.Add($androidLink)
$androidLink.Add_Click({
    $androidPath = Join-Path $base $androidConfigName
    if (-not (Test-Path $androidPath)) {
        [System.Windows.Forms.MessageBox]::Show("Import a VPN .conf file first - the Android config is generated from it.", "Nothing to send yet", "OK", "Information") | Out-Null
        return
    }

    $url = Start-AndroidHandoff
    if (-not $url) {
        # No LAN address to serve on - fall back to handing over the file
        Start-Process "explorer.exe" -ArgumentList "/select,`"$androidPath`""
        [System.Windows.Forms.MessageBox]::Show("Couldn't start the local handoff, so here's the file instead:`n`n$androidConfigName`n`nCopy it to your phone and use Import from file in sing-box.", "Android config", "OK", "Information") | Out-Null
        return
    }

    Show-PhoneHandoffDialog $url
    Stop-AndroidHandoff
})

$form.Add_FormClosing({ Stop-AndroidHandoff })

# ---------- Divider + credit row (avatar + made by mingal, bottom) ----------
$divider = New-Object System.Windows.Forms.Panel
$divider.Size = New-Object System.Drawing.Size(400, 1)
$divider.Location = New-Object System.Drawing.Point(20, 422)
$divider.BackColor = [System.Drawing.Color]::FromArgb(235, 235, 238)
$form.Controls.Add($divider)

$creditPill = New-Object System.Windows.Forms.Panel
$creditPill.Size = New-Object System.Drawing.Size(168, 34)
$creditPill.Location = New-Object System.Drawing.Point(136, 436)
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
    # bind_interface names the physical adapter explicitly. route's
    # auto_detect_interface would be tidier, but it reads the routing table -
    # where auto_route has already made the TUN the default - so it binds the
    # direct outbound to the tunnel itself and every UDP flow dies as a
    # "loopback connection to TUN range". The name written here is refreshed on
    # each launch by tunnel-launcher.ps1, so it still follows the adapter in
    # use without a reconfigure.
    #
    # domain_resolver is kept because sing-box refuses a detour into an
    # outbound carrying no explicit dial fields of its own ("detour to an
    # empty direct outbound makes no sense").
    $directOutbound = [ordered]@{ type = "direct"; tag = "direct"; domain_resolver = "dns-direct" }
    $physicalInterface = Get-PhysicalInterfaceAlias
    if ($physicalInterface) { $directOutbound["bind_interface"] = $physicalInterface }
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
        default_domain_resolver = "dns-direct"
        rules = @(
            # auto_route points the TUN's own DNS at an address inside the TUN
            # subnet, so without hijacking, every lookup the machine makes is
            # treated as ordinary traffic aimed at that address and rejected
            # ("loopback connection to TUN range"). Windows then falls back to
            # the physical adapter's resolver, which works but is slow, floods
            # the log, and skips the dns block entirely - meaning Discord's
            # lookups never take the dns-vpn path they're routed to below.
            [ordered]@{ action = "sniff" }
            [ordered]@{ protocol = "dns"; action = "hijack-dns" }
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

    Write-AndroidConfig $endpointAddresses $allowedIps $privateKey $endpointHost $endpointPort $publicKey $dnsStrategy

    Set-Progress "Config file created." $LogGreen
    return $true
}

$androidConfigName = "discord-tunneling-android.json"
$androidHandoffPort = 8899
$script:androidHandoff = $null

$script:qrTypeLoaded = $false

function Initialize-QrEncoder {
    # Compiled on first use rather than at startup - the app opens instantly
    # for everyone who never touches the Android handoff.
    if ($script:qrTypeLoaded) { return $true }
    $qrSource = @'
// Minimal QR encoder: byte mode, EC level L, versions 1-10.
// Enough for a sing-box import deep link (~110 bytes) and nothing more.
using System;
using System.Collections.Generic;

public static class QrLite
{
    // Data codewords per version at EC level L
    static readonly int[] DataCw = { 0, 19, 34, 55, 80, 108, 136, 156, 194, 232, 274 };
    // EC codewords per block, at EC level L
    static readonly int[] EcPerBlock = { 0, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18 };
    // Blocks per version: {group1 count, group2 count}
    static readonly int[][] Blocks = {
        null,
        new[]{1,0}, new[]{1,0}, new[]{1,0}, new[]{1,0}, new[]{1,0},
        new[]{2,0}, new[]{2,0}, new[]{2,0}, new[]{2,0}, new[]{2,2}
    };
    static readonly int[][] AlignPos = {
        null, new int[]{}, new[]{6,18}, new[]{6,22}, new[]{6,26}, new[]{6,30},
        new[]{6,34}, new[]{6,22,38}, new[]{6,24,42}, new[]{6,26,46}, new[]{6,28,50}
    };
    static readonly int[] VersionInfo = { 0,0,0,0,0,0,0, 0x07C94, 0x085BC, 0x09A99, 0x0A4D3 };

    static int[] expTable = new int[512];
    static int[] logTable = new int[256];

    static QrLite()
    {
        int x = 1;
        for (int i = 0; i < 255; i++)
        {
            expTable[i] = x;
            logTable[x] = i;
            x <<= 1;
            if ((x & 0x100) != 0) x ^= 0x11D;
        }
        for (int i = 255; i < 512; i++) expTable[i] = expTable[i - 255];
    }

    static int Mul(int a, int b)
    {
        if (a == 0 || b == 0) return 0;
        return expTable[logTable[a] + logTable[b]];
    }

    static int[] GenPoly(int degree)
    {
        int[] poly = new int[] { 1 };
        for (int i = 0; i < degree; i++)
        {
            int[] next = new int[poly.Length + 1];
            for (int j = 0; j < poly.Length; j++)
            {
                next[j] ^= poly[j];
                next[j + 1] ^= Mul(poly[j], expTable[i]);
            }
            poly = next;
        }
        return poly;
    }

    static int[] EcCodewords(int[] data, int ecLen)
    {
        int[] gen = GenPoly(ecLen);
        int[] rem = new int[ecLen];
        for (int i = 0; i < data.Length; i++)
        {
            int factor = data[i] ^ rem[0];
            Array.Copy(rem, 1, rem, 0, ecLen - 1);
            rem[ecLen - 1] = 0;
            for (int j = 0; j < ecLen; j++)
                rem[j] ^= Mul(gen[j + 1], factor);
        }
        return rem;
    }

    public static bool[,] Encode(string text)
    {
        byte[] payload = System.Text.Encoding.UTF8.GetBytes(text);

        int version = 0;
        for (int v = 1; v <= 10; v++)
        {
            int countBits = (v <= 9) ? 8 : 16;
            int capacity = DataCw[v] - 1 - (countBits / 8);
            if (payload.Length <= capacity) { version = v; break; }
        }
        if (version == 0) throw new Exception("payload too large for version 10");

        int size = version * 4 + 17;
        int charCountBits = (version <= 9) ? 8 : 16;

        // --- bit stream: mode(0100) + count + data + terminator + pad ---
        var bits = new List<bool>();
        AddBits(bits, 4, 4);                      // byte mode
        AddBits(bits, payload.Length, charCountBits);
        foreach (byte b in payload) AddBits(bits, b, 8);

        int totalDataBits = DataCw[version] * 8;
        int term = Math.Min(4, totalDataBits - bits.Count);
        AddBits(bits, 0, term);
        while (bits.Count % 8 != 0) bits.Add(false);
        int padByte = 0xEC;
        while (bits.Count < totalDataBits)
        {
            AddBits(bits, padByte, 8);
            padByte = (padByte == 0xEC) ? 0x11 : 0xEC;
        }

        int[] dataCw = new int[DataCw[version]];
        for (int i = 0; i < dataCw.Length; i++)
        {
            int val = 0;
            for (int j = 0; j < 8; j++) val = (val << 1) | (bits[i * 8 + j] ? 1 : 0);
            dataCw[i] = val;
        }

        // --- split into blocks, compute EC, interleave ---
        int g1 = Blocks[version][0], g2 = Blocks[version][1];
        int totalBlocks = g1 + g2;
        int ecLen = EcPerBlock[version];
        int shortLen = DataCw[version] / totalBlocks;

        var dataBlocks = new List<int[]>();
        var ecBlocks = new List<int[]>();
        int pos = 0;
        for (int b = 0; b < totalBlocks; b++)
        {
            int len = shortLen + (b < g1 ? 0 : 1);
            int[] blk = new int[len];
            Array.Copy(dataCw, pos, blk, 0, len);
            pos += len;
            dataBlocks.Add(blk);
            ecBlocks.Add(EcCodewords(blk, ecLen));
        }

        var final = new List<int>();
        int maxLen = shortLen + (g2 > 0 ? 1 : 0);
        for (int i = 0; i < maxLen; i++)
            foreach (var blk in dataBlocks)
                if (i < blk.Length) final.Add(blk[i]);
        for (int i = 0; i < ecLen; i++)
            foreach (var blk in ecBlocks)
                final.Add(blk[i]);

        // --- matrix ---
        bool[,] mod = new bool[size, size];
        bool[,] used = new bool[size, size];

        PlaceFinder(mod, used, 0, 0, size);
        PlaceFinder(mod, used, size - 7, 0, size);
        PlaceFinder(mod, used, 0, size - 7, size);

        for (int i = 8; i < size - 8; i++)
        {
            bool dark = (i % 2 == 0);
            mod[i, 6] = dark; used[i, 6] = true;
            mod[6, i] = dark; used[6, i] = true;
        }

        int[] aligns = AlignPos[version];
        foreach (int ax in aligns)
            foreach (int ay in aligns)
            {
                if ((ax <= 8 && ay <= 8) || (ax <= 8 && ay >= size - 9) || (ax >= size - 9 && ay <= 8)) continue;
                for (int dx = -2; dx <= 2; dx++)
                    for (int dy = -2; dy <= 2; dy++)
                    {
                        bool dark = Math.Max(Math.Abs(dx), Math.Abs(dy)) != 1;
                        mod[ax + dx, ay + dy] = dark;
                        used[ax + dx, ay + dy] = true;
                    }
            }

        // dark module + reserve format areas
        mod[8, size - 8] = true; used[8, size - 8] = true;
        for (int i = 0; i < 9; i++)
        {
            if (!used[i, 8]) { used[i, 8] = true; }
            if (!used[8, i]) { used[8, i] = true; }
        }
        for (int i = 0; i < 8; i++)
        {
            used[size - 1 - i, 8] = true;
            used[8, size - 1 - i] = true;
        }
        if (version >= 7)
            for (int i = 0; i < 6; i++)
                for (int j = 0; j < 3; j++)
                {
                    used[i, size - 11 + j] = true;
                    used[size - 11 + j, i] = true;
                }

        // --- data placement, zigzag from bottom-right ---
        int bitIdx = 0;
        int totalBits = final.Count * 8;
        bool upward = true;
        for (int col = size - 1; col >= 1; col -= 2)
        {
            if (col == 6) col = 5;
            for (int r = 0; r < size; r++)
            {
                int row = upward ? size - 1 - r : r;
                for (int c = 0; c < 2; c++)
                {
                    int cc = col - c;
                    if (used[cc, row]) continue;
                    bool bit = false;
                    if (bitIdx < totalBits)
                    {
                        int by = final[bitIdx / 8];
                        bit = ((by >> (7 - (bitIdx % 8))) & 1) == 1;
                    }
                    bitIdx++;
                    mod[cc, row] = bit;
                }
            }
            upward = !upward;
        }

        // --- pick mask by penalty ---
        int bestMask = 0, bestScore = int.MaxValue;
        bool[,] bestGrid = null;
        for (int m = 0; m < 8; m++)
        {
            bool[,] test = (bool[,])mod.Clone();
            ApplyMask(test, used, size, m);
            PlaceFormat(test, size, m);
            if (version >= 7) PlaceVersion(test, size, version);
            int score = Penalty(test, size);
            if (score < bestScore) { bestScore = score; bestMask = m; bestGrid = test; }
        }
        return bestGrid;
    }

    static void AddBits(List<bool> bits, int value, int count)
    {
        for (int i = count - 1; i >= 0; i--) bits.Add(((value >> i) & 1) == 1);
    }

    static void PlaceFinder(bool[,] mod, bool[,] used, int x, int y, int size)
    {
        for (int dx = -1; dx <= 7; dx++)
            for (int dy = -1; dy <= 7; dy++)
            {
                int px = x + dx, py = y + dy;
                if (px < 0 || py < 0 || px >= size || py >= size) continue;
                bool dark = (dx >= 0 && dx <= 6 && dy >= 0 && dy <= 6) &&
                            (dx == 0 || dx == 6 || dy == 0 || dy == 6 ||
                             (dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4));
                mod[px, py] = dark;
                used[px, py] = true;
            }
    }

    static bool MaskAt(int m, int x, int y)
    {
        switch (m)
        {
            case 0: return (x + y) % 2 == 0;
            case 1: return y % 2 == 0;
            case 2: return x % 3 == 0;
            case 3: return (x + y) % 3 == 0;
            case 4: return (y / 2 + x / 3) % 2 == 0;
            case 5: return (x * y) % 2 + (x * y) % 3 == 0;
            case 6: return ((x * y) % 2 + (x * y) % 3) % 2 == 0;
            default: return ((x + y) % 2 + (x * y) % 3) % 2 == 0;
        }
    }

    static void ApplyMask(bool[,] mod, bool[,] used, int size, int m)
    {
        for (int x = 0; x < size; x++)
            for (int y = 0; y < size; y++)
                if (!used[x, y] && MaskAt(m, x, y))
                    mod[x, y] = !mod[x, y];
    }

    static void PlaceFormat(bool[,] mod, int size, int mask)
    {
        int data = (1 << 3) | mask;            // EC level L == 01, shifted
        data = (0x01 << 3) | mask;
        int rem = data;
        for (int i = 0; i < 10; i++) rem = (rem << 1) ^ (((rem >> 9) != 0) ? 0x537 : 0);
        int fmt = ((data << 10) | rem) ^ 0x5412;

        for (int i = 0; i <= 5; i++) mod[8, i] = ((fmt >> i) & 1) == 1;
        mod[8, 7] = ((fmt >> 6) & 1) == 1;
        mod[8, 8] = ((fmt >> 7) & 1) == 1;
        mod[7, 8] = ((fmt >> 8) & 1) == 1;
        for (int i = 9; i < 15; i++) mod[14 - i, 8] = ((fmt >> i) & 1) == 1;

        for (int i = 0; i < 8; i++) mod[size - 1 - i, 8] = ((fmt >> i) & 1) == 1;
        for (int i = 8; i < 15; i++) mod[8, size - 15 + i] = ((fmt >> i) & 1) == 1;
    }

    static void PlaceVersion(bool[,] mod, int size, int version)
    {
        int info = VersionInfo[version];
        for (int i = 0; i < 18; i++)
        {
            bool bit = ((info >> i) & 1) == 1;
            int a = i / 3, b = i % 3;
            mod[a, size - 11 + b] = bit;
            mod[size - 11 + b, a] = bit;
        }
    }

    static int Penalty(bool[,] m, int size)
    {
        int score = 0;
        // rule 1: runs of 5+
        for (int dir = 0; dir < 2; dir++)
            for (int a = 0; a < size; a++)
            {
                int run = 1;
                bool prev = dir == 0 ? m[0, a] : m[a, 0];
                for (int b = 1; b < size; b++)
                {
                    bool cur = dir == 0 ? m[b, a] : m[a, b];
                    if (cur == prev) run++;
                    else { if (run >= 5) score += 3 + (run - 5); run = 1; prev = cur; }
                }
                if (run >= 5) score += 3 + (run - 5);
            }
        // rule 2: 2x2 blocks
        for (int x = 0; x < size - 1; x++)
            for (int y = 0; y < size - 1; y++)
                if (m[x, y] == m[x + 1, y] && m[x, y] == m[x, y + 1] && m[x, y] == m[x + 1, y + 1])
                    score += 3;
        // rule 3: finder-like patterns
        for (int dir = 0; dir < 2; dir++)
            for (int a = 0; a < size; a++)
                for (int b = 0; b < size - 6; b++)
                {
                    bool[] p = new bool[7];
                    for (int k = 0; k < 7; k++) p[k] = dir == 0 ? m[b + k, a] : m[a, b + k];
                    if (p[0] && !p[1] && p[2] && p[3] && p[4] && !p[5] && p[6]) score += 40;
                }
        // rule 4: dark ratio
        int dark = 0;
        foreach (bool v in m) if (v) dark++;
        int pct = dark * 100 / (size * size);
        score += Math.Abs(pct - 50) / 5 * 10;
        return score;
    }
}
'@
    try {
        Add-Type -TypeDefinition $qrSource -ErrorAction Stop
        $script:qrTypeLoaded = $true
        return $true
    } catch {
        return $false
    }
}

function New-QrBitmap($text, $scale = 7, $quiet = 3) {
    if (-not (Initialize-QrEncoder)) { return $null }
    try { $matrix = [QrLite]::Encode($text) } catch { return $null }
    $size = [int][Math]::Sqrt($matrix.Length)
    $dim = ($size + $quiet * 2) * $scale
    $bmp = New-Object System.Drawing.Bitmap($dim, $dim)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::White)
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Black)
    for ($x = 0; $x -lt $size; $x++) {
        for ($y = 0; $y -lt $size; $y++) {
            if ($matrix[$x, $y]) {
                $g.FillRectangle($brush, ($x + $quiet) * $scale, ($y + $quiet) * $scale, $scale, $scale)
            }
        }
    }
    $brush.Dispose()
    $g.Dispose()
    return $bmp
}

function Get-LanIPAddress {
    $iface = Get-PhysicalInterfaceAlias
    if (-not $iface) { return $null }
    $ip = Get-NetIPAddress -InterfaceAlias $iface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike "169.254.*" } | Select-Object -First 1
    if ($ip) { return $ip.IPAddress }
    return $null
}

function Stop-AndroidHandoff {
    if (-not $script:androidHandoff) { return }
    try { $script:androidHandoff.State.Stop = $true } catch { }
    try { $script:androidHandoff.PowerShell.Stop() } catch { }
    try { $script:androidHandoff.PowerShell.Dispose() } catch { }
    try { $script:androidHandoff.Runspace.Close() } catch { }
    $script:androidHandoff = $null
}

function Start-AndroidHandoff {
    # Hands the phone its profile over the local network instead of asking
    # anyone to copy a file around. sing-box for Android registers a
    # sing-box://import-remote-profile URL scheme, so a page served here can
    # import the profile in one tap - and the key never leaves the LAN.
    Stop-AndroidHandoff

    $ip = Get-LanIPAddress
    if (-not $ip) { return $null }
    $configPath = Join-Path $base $androidConfigName
    if (-not (Test-Path $configPath)) { return $null }

    $state = [hashtable]::Synchronized(@{ Stop = $false; Served = 0 })
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions = "ReuseThread"
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable("srvState", $state)
    $runspace.SessionStateProxy.SetVariable("srvPort", $androidHandoffPort)
    $runspace.SessionStateProxy.SetVariable("srvIp", $ip)
    $runspace.SessionStateProxy.SetVariable("srvConfigPath", $configPath)

    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript({
        $listener = New-Object System.Net.HttpListener
        # The app runs elevated, so binding a wildcard prefix needs no separate
        # URL ACL registration.
        $listener.Prefixes.Add("http://+:$srvPort/")
        try { $listener.Start() } catch { return }

        $profileUrl = "http://$srvIp`:$srvPort/profile.json"
        $deepLink = "sing-box://import-remote-profile?url=" +
            [uri]::EscapeDataString($profileUrl) + "#" +
            [uri]::EscapeDataString("Discord Tunneling")

        $page = @"
<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Discord Tunneling</title><style>
body{margin:0;font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#faf7f9;color:#2b2b33;
display:flex;min-height:100vh;align-items:center;justify-content:center;padding:24px}
.card{background:#fff;border-radius:18px;padding:28px 24px;max-width:420px;width:100%;
box-shadow:0 8px 30px rgba(0,0,0,.08);text-align:center}
h1{font-size:20px;margin:0 0 6px;color:#c6307e}
p{font-size:14px;line-height:1.5;color:#5a5a66;margin:0 0 20px}
a.btn{display:block;background:#f657a9;color:#fff;text-decoration:none;font-weight:600;
font-size:16px;padding:15px;border-radius:12px;margin-bottom:14px}
ol{text-align:left;font-size:13px;color:#5a5a66;line-height:1.7;padding-left:20px;margin:0}
.small{font-size:12px;color:#8a8a96;margin-top:18px}
.url{font-family:ui-monospace,Consolas,monospace;font-size:13px;word-break:break-all;
background:#f6f2f4;border:1px solid #ecdfe6;border-radius:10px;padding:11px;color:#3a3a44}
button.copy{margin:10px 0 18px;background:#fff;border:1.5px solid #f657a9;color:#c6307e;
font-weight:600;font-size:14px;padding:10px 18px;border-radius:10px}
</style></head><body><div class="card">
<h1>Discord Tunneling</h1>
<p>Only Discord goes through your VPN. Everything else on this phone keeps its normal connection.</p>
<a class="btn" href="$deepLink">Import into sing-box</a>
<p class="small" style="margin:-6px 0 16px">If that button does nothing, use the address below instead &mdash; some browsers refuse to hand off custom links.</p>
<div class="url" id="u">$profileUrl</div>
<button class="copy" onclick="navigator.clipboard.writeText(document.getElementById('u').textContent);this.textContent='Copied'">Copy address</button>
<ol>
<li>Install <b>sing-box</b> from Google Play or F-Droid, if you haven't.</li>
<li>In sing-box: <b>New profile</b>, set <b>Type</b> to <b>Remote</b>, paste the address as the URL, and save.</li>
<li>Switch it on from the Dashboard.</li>
</ol>
<p class="small">Nothing to configure afterwards: Discord is already the only app routed through it. Don't open sing-box's per-app proxy screen &mdash; it overrides this.</p>
</div></body></html>
"@

        while (-not $srvState.Stop) {
            $ctx = $null
            try {
                $task = $listener.GetContextAsync()
                while (-not $task.AsyncWaitHandle.WaitOne(400)) {
                    if ($srvState.Stop) { break }
                }
                if ($srvState.Stop) { break }
                $ctx = $task.GetAwaiter().GetResult()
            } catch { break }
            if (-not $ctx) { continue }

            try {
                $path = $ctx.Request.Url.AbsolutePath
                if ($path -eq "/profile.json") {
                    $bytes = [System.IO.File]::ReadAllBytes($srvConfigPath)
                    $ctx.Response.ContentType = "application/json"
                    $srvState.Served = $srvState.Served + 1
                } else {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($page)
                    $ctx.Response.ContentType = "text/html; charset=utf-8"
                }
                $ctx.Response.ContentLength64 = $bytes.Length
                $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                $ctx.Response.OutputStream.Close()
            } catch { }
        }
        try { $listener.Stop() } catch { }
        try { $listener.Close() } catch { }
    })
    [void]$ps.BeginInvoke()

    $script:androidHandoff = @{
        Runspace = $runspace; PowerShell = $ps; State = $state
        Url = "http://$ip`:$androidHandoffPort"
    }
    return $script:androidHandoff.Url
}
# Discord's Play Store package. Anything else (a beta build, a fork) can be
# added to this list and the file regenerated.
$androidPackages = @("com.discord")

function Write-AndroidConfig($endpointAddresses, $allowedIps, $privateKey, $endpointHost, $endpointPort, $publicKey, $dnsStrategy) {
    # Android does per-app VPN properly - VpnService takes a package list - so
    # the same .conf produces a phone profile with Discord already isolated,
    # with nothing to tick in sing-box's UI after importing.
    #
    # None of the Windows workarounds carry over: include_package filters at
    # the TUN itself, so everything that reaches sing-box is already Discord
    # and the route can simply end at the tunnel. And VpnService protects
    # sing-box's own sockets from the VPN it created, which is what
    # bind_interface and the endpoint detour exist to do on Windows.
    $tunAddresses = @("172.19.0.1/30")
    if ($endpointAddresses.Count -gt 1) { $tunAddresses += "fdfe:dcba:9876::1/126" }

    $androidConfig = [ordered]@{
        log = [ordered]@{ level = "warn" }
        dns = [ordered]@{
            servers = @(
                [ordered]@{ type = "udp"; tag = "dns-vpn"; server = "1.1.1.1"; server_port = 53; detour = "vpn" }
            )
            strategy = $dnsStrategy
            final = "dns-vpn"
        }
        endpoints = @(
            [ordered]@{
                type = "wireguard"
                tag = "vpn"
                system = $false
                address = $endpointAddresses
                private_key = $privateKey
                mtu = 1408
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
        )
        inbounds = @(
            [ordered]@{
                type = "tun"
                tag = "tun-in"
                address = $tunAddresses
                mtu = 1400
                auto_route = $true
                stack = "system"
                # Android-only, and requires auto_route: only these packages
                # are routed into the tunnel. Everything else on the phone
                # never touches it.
                include_package = $androidPackages
            }
        )
        outbounds = @(
            [ordered]@{ type = "direct"; tag = "direct" }
        )
        route = [ordered]@{
            default_domain_resolver = "dns-vpn"
            rules = @(
                [ordered]@{ action = "sniff" }
                [ordered]@{ protocol = "dns"; action = "hijack-dns" }
            )
            final = "vpn"
        }
    }

    $androidPath = Join-Path $base $androidConfigName
    $androidJson = $androidConfig | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($androidPath, $androidJson, (New-Object System.Text.UTF8Encoding($false)))
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

function Write-TunnelLauncher {
    # sing-box is started through this rather than directly so the adapter
    # named in bind_interface is refreshed first. Otherwise the adapter chosen
    # when the .conf was imported would be baked in, and the tunnel would break
    # the first time the machine moved from Ethernet to Wi-Fi.
    $launcherPath = Join-Path $base "tunnel-launcher.ps1"
    $launcher = @'
# $PSScriptRoot first: $MyInvocation.MyCommand.Path comes back empty in some
# unattended hosts, and this runs at logon where a null path fails silently.
$base = $PSScriptRoot
if (-not $base) { $base = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $base) { exit 1 }
Set-Location $base

function Get-PhysicalInterfaceAlias {
    # Skip sing-box's own TUN: with auto_route it owns the default route, and
    # binding the direct outbound to it makes every UDP flow fail as a
    # "loopback connection to TUN range".
    try {
        $routes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction Stop | Sort-Object -Property RouteMetric
        foreach ($r in $routes) {
            $adapter = Get-NetAdapter -InterfaceIndex $r.InterfaceIndex -ErrorAction SilentlyContinue
            if ($adapter -and $adapter.Status -eq "Up" -and
                $adapter.Name -notlike "tun*" -and
                $adapter.InterfaceDescription -notlike "*sing-tun*") {
                return $adapter.Name
            }
        }
    } catch { }
    return $null
}

# Never start a second instance. Two sing-box processes sharing one WireGuard
# key make the VPN server bounce the session between them, and the tunnel
# carries no data at all while that happens.
if (Get-Process -Name "sing-box" -ErrorAction SilentlyContinue) { exit 0 }

$configPath = Join-Path $base "config.json"
$iface = Get-PhysicalInterfaceAlias
if ($iface -and (Test-Path $configPath)) {
    try {
        $cfg = Get-Content -Raw $configPath | ConvertFrom-Json
        $direct = $cfg.outbounds | Where-Object { $_.tag -eq "direct" } | Select-Object -First 1
        if ($direct -and $direct.bind_interface -ne $iface) {
            $direct | Add-Member -NotePropertyName bind_interface -NotePropertyValue $iface -Force
            $json = $cfg | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($configPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        }
    } catch { }
}

# Discard a runaway log while nothing holds it open
$logPath = Join-Path $base "sing-box.log"
if ((Test-Path $logPath) -and ((Get-Item $logPath).Length -gt 20MB)) {
    Remove-Item $logPath -Force -ErrorAction SilentlyContinue
}

& (Join-Path $base "sing-box.exe") run -c config.json
'@
    [System.IO.File]::WriteAllText($launcherPath, $launcher, (New-Object System.Text.UTF8Encoding($false)))
    return $launcherPath
}

function Remove-LegacyAutostart {
    # Cleans up the old (pre-TUN) SOCKS5-based autostart mechanism, which
    # launched sing-box non-elevated and would silently fail to create a
    # TUN adapter if left in place alongside the new scheduled task.
    $startupFolder = [Environment]::GetFolderPath("Startup")
    foreach ($stale in @("sing-box-vpn.lnk", "sing-box-proton.lnk")) {
        $p = Join-Path $startupFolder $stale
        if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
    }
    $vbsPath = Join-Path $base "iniciar.vbs"
    if (Test-Path $vbsPath) { Remove-Item $vbsPath -Force }
}

function Set-DiscordStartupWaiter($enable) {
    # A "Discord (Tunneling)" shortcut left in the Startup folder by v1.x still
    # carried --proxy-server=socks5://127.0.0.1:1080. That proxy stopped
    # existing in 2.0, and Chromium pointed at a dead proxy refuses every
    # connection, so Discord hung on "Starting..." at every boot while the same
    # shortcut on the desktop (already rewritten) worked fine.
    #
    # Replacing it with a waiter fixes more than the dead flag: Discord is held
    # until the tunnel adapter is up, so its first connection already goes
    # through the VPN. Connecting beforehand would show Discord the real
    # location - the very restriction the tunnel exists to work around.
    $startupFolder = [Environment]::GetFolderPath("Startup")
    $startupShortcut = Join-Path $startupFolder "Discord (Tunneling).lnk"
    $waiterPath = Join-Path $base "discord-waiter.ps1"

    if (-not $enable) {
        if (Test-Path $startupShortcut) { Remove-Item $startupShortcut -Force -ErrorAction SilentlyContinue }
        if (Test-Path $waiterPath) { Remove-Item $waiterPath -Force -ErrorAction SilentlyContinue }
        return
    }

    $waiter = @'
$base = $PSScriptRoot
if (-not $base) { $base = Split-Path -Parent $MyInvocation.MyCommand.Path }

# Hold Discord until the tunnel adapter reports Up, so its first connection is
# already tunneled. Give up after two minutes and start it anyway - a Discord
# that opens untunneled beats one that never opens.
$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline) {
    $adapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.Status -eq "Up" -and ($_.Name -like "tun*" -or $_.InterfaceDescription -like "*sing-tun*") }
    if ($adapter) { Start-Sleep -Seconds 4; break }
    Start-Sleep -Seconds 2
}

if (-not (Get-Process -Name "Discord" -ErrorAction SilentlyContinue)) {
    $update = Join-Path $env:LOCALAPPDATA "Discord\Update.exe"
    if (Test-Path $update) {
        Start-Process -FilePath $update -ArgumentList "--processStart Discord.exe"
    }
}
'@
    [System.IO.File]::WriteAllText($waiterPath, $waiter, (New-Object System.Text.UTF8Encoding($false)))

    $WScriptShell = New-Object -ComObject WScript.Shell
    $s = $WScriptShell.CreateShortcut($startupShortcut)
    $s.TargetPath = "powershell.exe"
    $s.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$waiterPath`""
    $s.WorkingDirectory = $base
    $customIcon = Join-Path $base "assets\app.ico"
    if (Test-Path $customIcon) { $s.IconLocation = $customIcon }
    $s.Save()
}

function Set-Autostart($enable) {
    Remove-LegacyAutostart
    Set-DiscordStartupWaiter $enable
    Unregister-ScheduledTask -TaskName $autostartTaskName -Confirm:$false -ErrorAction SilentlyContinue

    if ($enable) {
        # TUN needs Administrator rights, so autostart uses a scheduled task
        # registered to run elevated at logon instead of a plain Startup
        # shortcut (which Windows cannot silently elevate).
        $launcherPath = Write-TunnelLauncher
        $action = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$launcherPath`"" `
            -WorkingDirectory $base

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
        # sing-box names the adapter "tun0" and describes it as "sing-tun
        # Tunnel" - not "Wintun", which is only the driver underneath it.
        $adapter = Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -eq "Up" -and
                ($_.InterfaceDescription -like "*sing-tun*" -or
                 $_.InterfaceDescription -like "*Wintun*" -or
                 $_.Name -like "tun*") }
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
        # The .conf was already imported, so starting is all that's left.
        # Making someone re-pick the same file to get the tunnel back reads as
        # the config not having been saved at all.
        $form.Add_Shown({
            if ((Test-TunnelInstalled) -and -not (Test-TunnelRunning)) {
                Set-Status "Starting tunnel..." $LogYellow
                Start-Tunnel | Out-Null
            }
        })
    }
    $openButton.Enabled = $true
    $installButton.Text = "Reconfigure (select a different .conf)"
} else {
    Set-Progress "Ready." $LogGray
}

[System.Windows.Forms.Application]::Run($form)
