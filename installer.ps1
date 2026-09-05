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

$iconPath = Join-Path $base "assets\app.ico"
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

function Ensure-SingBox {
    $singboxExe = Join-Path $base "sing-box.exe"
    if (Test-Path $singboxExe) {
        Set-Progress "sing-box already present." $LogGreen
        return $true
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

    $addressIPv4 = ($addressRaw -split ",")[0].Trim()
    $endpointParts = $endpoint -split ":"
    $endpointHost = $endpointParts[0]
    $endpointPort = $endpointParts[1]

    # If the VPN server is a literal IP, exclude it from the TUN's captured
    # routes so sing-box's own WireGuard handshake/keepalive packets keep
    # using the normal physical route instead of looping back into the TUN.
    # (Binding that dial to a specific interface via auto_detect_interface/
    # default_interface instead is a known sing-box/Windows incompatibility -
    # it errors with "listen udp6 ... address family not supported" whenever
    # the active adapter has IPv6 disabled, which blocks the handshake
    # entirely. See SagerNet/sing-box#2900.)
    $routeExcludeAddresses = @()
    if ($endpointHost -match '^\d{1,3}(\.\d{1,3}){3}$') {
        $routeExcludeAddresses += "$endpointHost/32"
    }

    # Discord's own process names, matched at the network layer so voice,
    # video and screen share (which are all UDP/WebRTC) get tunneled too -
    # a plain SOCKS5 proxy only ever carries the TCP/HTTP(S) traffic.
    $discordProcesses = @("Discord.exe", "Update.exe")

    $configObj = [ordered]@{
        dns = [ordered]@{
            servers = @(
                [ordered]@{ type = "local"; tag = "dns-direct" }
                [ordered]@{ type = "udp"; tag = "dns-vpn"; server = "1.1.1.1"; server_port = 53; detour = "vpn" }
            )
            rules = @(
                [ordered]@{ process_name = $discordProcesses; action = "route"; server = "dns-vpn" }
            )
            final = "dns-direct"
        }
        endpoints = @(
            [ordered]@{
                type = "wireguard"
                tag = "vpn"
                system = $false
                address = @($addressIPv4)
                private_key = $privateKey
                mtu = 1408
                peers = @(
                    [ordered]@{
                        address = $endpointHost
                        port = [int]$endpointPort
                        public_key = $publicKey
                        allowed_ips = @("0.0.0.0/0", "::/0")
                        persistent_keepalive_interval = 25
                    }
                )
            }
        )
        inbounds = @(
            [ordered]@{
                type = "tun"
                tag = "tun-in"
                address = @("172.19.0.1/30", "fdfe:dcba:9876::1/126")
                mtu = 1400
                auto_route = $true
                strict_route = $true
                stack = "system"
                route_exclude_address = $routeExcludeAddresses
            }
        )
        outbounds = @(
            [ordered]@{ type = "direct"; tag = "direct" }
        )
        route = [ordered]@{
            default_domain_resolver = "dns-direct"
            rules = @(
                [ordered]@{ process_name = $discordProcesses; action = "route"; outbound = "vpn" }
            )
            final = "direct"
        }
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
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -RunLevel Highest -LogonType Interactive
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName $autostartTaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    }
}

function Restart-Tunnel {
    # Always used after (re)writing config.json - a sing-box process already
    # running keeps using whatever config it loaded at launch, so a stale
    # process left over from a previous install/provider would silently keep
    # the old TUN/routing setup instead of the one just generated.
    if (Test-TunnelRunning) {
        Get-Process -Name "sing-box" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }
    Start-Tunnel
}

function Start-Tunnel {
    if (Test-TunnelRunning) {
        Set-Status "Tunnel running" $LogGreen
        return
    }
    $singboxExe = Join-Path $base "sing-box.exe"
    Start-Process -FilePath $singboxExe -ArgumentList "run -c config.json" -WorkingDirectory $base -WindowStyle Hidden
    Start-Sleep -Seconds 1
    if (Test-TunnelRunning) {
        Set-Progress "Tunnel started." $LogGreen
        Set-Status "Tunnel running" $LogGreen
    } else {
        Set-Progress "Tunnel failed to start." $LogRed
        Set-Status "Tunnel failed to start" $LogRed
    }
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
    Set-Autostart $autostartCheck.Checked
    Restart-Tunnel

    $openButton.Enabled = $true
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
