# ==============================================================================
#  [CORESYSTEM | ADVANCED WINDOWS OS DEPLOYMENT - NG]
#  Next-Generation: 100% WPF UI, no console interaction for rescue tools.
#  Deployment console is wrapped in a XAML frame (decorative only).
# ==============================================================================

$ProgressPreference = 'SilentlyContinue'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

# 1. WINAPI STRUCTURES FOR CONSOLE MANAGEMENT
$WinAPI_Canvas = @"
using System;
using System.Runtime.InteropServices;
public class WinPEConsole {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int nIndex);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern IntPtr SetParent(IntPtr hWndChild, IntPtr hWndNewParent);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);
}
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public struct POINT { public int X; public int Y; }
"@
Add-Type -TypeDefinition $WinAPI_Canvas -ErrorAction SilentlyContinue

$global:hConsole = [WinPEConsole]::GetForegroundWindow()

function Set-ConsoleState {
    param ([string]$Mode)
    if ($global:hConsole -ne [IntPtr]::Zero) {
        if ($Mode -eq "Hide") {
            [WinPEConsole]::MoveWindow($global:hConsole, -2000, -2000, 300, 100, $true) | Out-Null
        }
        elseif ($Mode -eq "Show") {
            $ScreenWidth  = [WinPEConsole]::GetSystemMetrics(0)
            $ScreenHeight = [WinPEConsole]::GetSystemMetrics(1)
            $Width  = 760; $Height = 460
            $X = [Math]::Max(0, [int](($ScreenWidth - $Width) / 2))
            $Y = [Math]::Max(0, [int](($ScreenHeight - $Height) / 2))
            try {
                $BufSize = New-Object System.Management.Automation.Host.Size(90, 25)
                $Host.UI.RawUI.BufferSize = $BufSize
                $Host.UI.RawUI.WindowSize = $BufSize
            } catch {}
            [WinPEConsole]::MoveWindow($global:hConsole, $X, $Y, $Width, $Height, $true) | Out-Null
            [WinPEConsole]::ShowWindow($global:hConsole, 9) | Out-Null
        }
    }
}

# ------------------------------------------------------------------------------
# GLOBAL VARIABLES
# ------------------------------------------------------------------------------
$global:DeployMode    = "Vanilla"
$global:ConfirmDeploy = $false
$global:HasBitLocker  = $false
$global:BitLockerState = "None"
$global:ConfigData    = $null
$global:HasInternet   = $false
$global:WifiDialogOpen = $false
$global:WifiCooldown   = $null

try {
    $OSDModule = Get-Module -Name OSDCloud -ListAvailable | Select-Object -First 1
    if ($OSDModule) {
        $global:OSDPath = $OSDModule.ModuleBase
        $global:OsdCloudJsonPath = Join-Path $global:OSDPath "workflow\cli\os-amd64.json"
    } else {
        $global:OsdCloudJsonPath = Join-Path $PSScriptRoot "os-amd64.json"
    }
} catch {
    $global:OsdCloudJsonPath = Join-Path $PSScriptRoot "os-amd64.json"
}

# ------------------------------------------------------------------------------
# HARDWARE MONITOR — refreshes all spec labels in the main window
# ------------------------------------------------------------------------------
function Refresh-Hardware-Specs {
    $BootMode = "Unknown"; $SecureBoot = "Unknown"; $TPMStatus = "NOT FOUND"

    try { if ($env:Firmware_Type -eq "UEFI") { $BootMode = "UEFI" } else { $BootMode = "Legacy" } } catch { $BootMode = "ERROR" }
    try { if (Confirm-SecureBootUEFI -ErrorAction SilentlyContinue) { $SecureBoot = "ON" } else { $SecureBoot = "OFF" } } catch { $SecureBoot = "UNSUPPORTED" }
    try {
        $TpmWmi = Get-CimInstance -Namespace "Root\CIMv2\Security\MicrosoftTpm" -ClassName "Win32_Tpm" -ErrorAction SilentlyContinue
        if ($TpmWmi) {
            $RawVersion = $TpmWmi.SpecVersion
            if ($RawVersion -match ",") { $TpmVersion = $RawVersion.Split(',')[0].Trim() } else { $TpmVersion = $RawVersion }
            $TPMStatus = "v$TpmVersion READY"
        } else { $TPMStatus = "NOT FOUND" }
    } catch { $TPMStatus = "DISABLE / NONE" }

    $global:txtSecuritySpecs.Text = "Boot: [$BootMode]  |  SB: [$SecureBoot]  |  TPM: [$TPMStatus]"

    try { $CPU = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue).Name.Trim(); $global:txtCPU.Text = "CPU : $CPU" } catch { $global:txtCPU.Text = "CPU : Generic Processor Module" }
    try { $RAMBytes = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory; $RAMGB = [Math]::Round($RAMBytes / 1GB); $global:txtRAM.Text = "RAM : ${RAMGB}GB " } catch { $global:txtRAM.Text = "RAM : 16GB Allocated Architecture" }
    try {
        $Disks = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue
        $TargetDisk = $Disks | Where-Object { $_.InterfaceType -ne "USB" -and $_.Model -notmatch "USB|TransMemory" } | Select-Object -First 1
        if (-not $TargetDisk) { $TargetDisk = $Disks | Select-Object -First 1 }
        if ($TargetDisk) { $SizeGB = [Math]::Round($TargetDisk.Size / 1GB); $global:txtDisk.Text = "Disk: $($TargetDisk.Model) ($SizeGB GB)" } else { $global:txtDisk.Text = "Disk: No Target Disk Found" }
    } catch { $global:txtDisk.Text = "Disk: Target Storage Evaluation Fault" }

    $global:HasInternet = $false
    try {
        $Network = Get-CimInstance Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -ne $null }
        if ($Network) {
            $IP = $Network.IPAddress[0]; $global:HasInternet = $true
            if ($Network.Description -match "Wireless|Wi-Fi|802.11|WLAN") { $global:txtIP.Text = "Net : [WIFI CONNECTED] - IP: $IP"; $global:txtIP.Foreground = [System.Windows.Media.Brushes]::LightGreen }
            else { $global:txtIP.Text = "Net : [LAN CONNECTED] - IP: $IP"; $global:txtIP.Foreground = [System.Windows.Media.Brushes]::Green }
        } else { $global:txtIP.Text = "Net : [NETWORK DISCONNECTED / STANDBY]"; $global:txtIP.Foreground = [System.Windows.Media.Brushes]::Yellow }
    } catch { $global:txtIP.Text = "Net : [IP ROUTING STANDBY MODE]"; $global:txtIP.Foreground = [System.Windows.Media.Brushes]::Yellow }

    try {
        $BdeStatus = manage-bde -status 2>$null | Out-String
        if ($BdeStatus -match "Lock Status:\s+Locked") {
            $global:BitLockerState = "Locked"; $global:HasBitLocker = $true
            $global:txtBitLocker.Text = "BitLocker: [ LOCKED DRIVES DETECTED ]"; $global:txtBitLocker.Foreground = [System.Windows.Media.Brushes]::Orange
        } elseif ($BdeStatus -match "BitLocker Version") {
            $global:BitLockerState = "Unlocked"; $global:HasBitLocker = $false
            $global:txtBitLocker.Text = "BitLocker: [ DRIVE UNLOCKED ]"; $global:txtBitLocker.Foreground = [System.Windows.Media.Brushes]::LightGreen
        } else {
            $global:BitLockerState = "None"; $global:HasBitLocker = $false
            $global:txtBitLocker.Text = "BitLocker: [ NO ENCRYPTED DRIVE ]"; $global:txtBitLocker.Foreground = [System.Windows.Media.Brushes]::Gray
        }
    } catch {
        $global:BitLockerState = "None"; $global:HasBitLocker = $false
        $global:txtBitLocker.Text = "BitLocker: [ NOT ACTIVE ]"; $global:txtBitLocker.Foreground = [System.Windows.Media.Brushes]::Gray
    }
}

function Invoke-AboutDialog {
    [System.Windows.MessageBox]::Show("CoreSystem Advanced OS Deployment System`n`nBuilt exclusively for Enterprise Infrastructure Deployment.`nWebsite: www.coresystem.vn`nAll rights reserved.", "About CoreSystem", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
}

# ==============================================================================
# MODULE 1: BITLOCKER WPF DIALOG
# Fully replaces the old console-based Invoke-BitLockerUnlock.
# XAML window: 8 TextBox x 6 digits, auto-advance on input,
# backspace-navigate, paste support, ComboBox for locked drive detection.
# Status feedback via inline TextBlock.
# ==============================================================================
function Invoke-BitLockerUnlock {
    try {
        $BdeCheck = manage-bde -status 2>$null | Out-String
        if ($BdeCheck -match "Lock Status:\s+Unlocked" -or ($BdeCheck -notmatch "Lock Status")) { return }
    } catch { return }

    $BitlockerXAML = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="BitLocker Decryption" Width="480" Height="380"
        Background="#0F172A" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" ShowInTaskbar="False">
    <Window.Resources>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#1E293B"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="#475569"/>
            <Setter Property="FontSize" Value="16"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="HorizontalContentAlignment" Value="Center"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="CaretBrush" Value="#38BDF8"/>
        </Style>
        <Style TargetType="Label">
            <Setter Property="Foreground" Value="#94A3B8"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="FontSize" Value="11"/>
        </Style>
    </Window.Resources>
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Text="BITLOCKER DECRYPTION" FontSize="14" FontWeight="Bold" Foreground="#38BDF8"/>
        <Rectangle Grid.Row="0" Height="2" Fill="#334155" Margin="0,25,0,0"/>

        <StackPanel Grid.Row="1" Margin="0,15,0,0">
            <Label Content="DETECTED LOCKED DRIVES:"/>
            <ComboBox x:Name="ComboDrives" Height="32" Background="#1E293B" Foreground="#FFFFFF" BorderBrush="#475569">
                <ComboBox.ItemContainerStyle>
                    <Style TargetType="ComboBoxItem">
                        <Setter Property="Background" Value="#1E293B"/>
                        <Setter Property="Foreground" Value="#FFFFFF"/>
                        <Setter Property="BorderBrush" Value="#334155"/>
                        <Setter Property="HorizontalContentAlignment" Value="Left"/>
                        <Setter Property="Padding" Value="8,4"/>
                    </Style>
                </ComboBox.ItemContainerStyle>
            </ComboBox>
        </StackPanel>

        <StackPanel Grid.Row="2" Margin="0,10,0,0">
            <Label Content="48-DIGIT RECOVERY KEY:"/>
        </StackPanel>

        <Grid Grid.Row="3" HorizontalAlignment="Center" Margin="0,5,0,0">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="72"/><ColumnDefinition Width="14"/>
                <ColumnDefinition Width="72"/><ColumnDefinition Width="14"/>
                <ColumnDefinition Width="72"/><ColumnDefinition Width="14"/>
                <ColumnDefinition Width="72"/>
            </Grid.ColumnDefinitions>
            <TextBox x:Name="Key1"  Grid.Row="0" Grid.Column="0" MaxLength="6" Height="36" BorderThickness="1" FontFamily="Consolas" FontSize="20"/>
            <TextBlock Grid.Row="0" Grid.Column="1" Text="-" Foreground="#475569" FontSize="22" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            <TextBox x:Name="Key2"  Grid.Row="0" Grid.Column="2" MaxLength="6" Height="36" BorderThickness="1" FontFamily="Consolas" FontSize="20"/>
            <TextBlock Grid.Row="0" Grid.Column="3" Text="-" Foreground="#475569" FontSize="22" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            <TextBox x:Name="Key3"  Grid.Row="0" Grid.Column="4" MaxLength="6" Height="36" BorderThickness="1" FontFamily="Consolas" FontSize="20"/>
            <TextBlock Grid.Row="0" Grid.Column="5" Text="-" Foreground="#475569" FontSize="22" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            <TextBox x:Name="Key4"  Grid.Row="0" Grid.Column="6" MaxLength="6" Height="36" BorderThickness="1" FontFamily="Consolas" FontSize="20"/>

            <TextBox x:Name="Key5"  Grid.Row="1" Grid.Column="0" MaxLength="6" Height="36" Margin="0,10,0,0" BorderThickness="1" FontFamily="Consolas" FontSize="20"/>
            <TextBlock Grid.Row="1" Grid.Column="1" Text="-" Foreground="#475569" FontSize="22" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,10,0,0"/>
            <TextBox x:Name="Key6"  Grid.Row="1" Grid.Column="2" MaxLength="6" Height="36" Margin="0,10,0,0" BorderThickness="1" FontFamily="Consolas" FontSize="20"/>
            <TextBlock Grid.Row="1" Grid.Column="3" Text="-" Foreground="#475569" FontSize="22" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,10,0,0"/>
            <TextBox x:Name="Key7"  Grid.Row="1" Grid.Column="4" MaxLength="6" Height="36" Margin="0,10,0,0" BorderThickness="1" FontFamily="Consolas" FontSize="20"/>
            <TextBlock Grid.Row="1" Grid.Column="5" Text="-" Foreground="#475569" FontSize="22" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,10,0,0"/>
            <TextBox x:Name="Key8"  Grid.Row="1" Grid.Column="6" MaxLength="6" Height="36" Margin="0,10,0,0" BorderThickness="1" FontFamily="Consolas" FontSize="20"/>
        </Grid>

        <TextBlock Grid.Row="4" Text="[i] Paste 48-digit key anywhere to fill all fields" Foreground="#64748B" FontSize="10" Margin="0,10,0,0"/>

        <TextBlock x:Name="TxtStatus" Grid.Row="5" Text="Status: Ready" Foreground="#475569" FontSize="11" VerticalAlignment="Bottom" Margin="0,10,0,0"/>

        <Grid Grid.Row="6" Margin="0,10,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="10"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Border CornerRadius="4" Grid.Column="0">
                <Button x:Name="BtnUnlock" Content="UNLOCK DRIVE" Height="38" Background="#10B981" Foreground="#FFFFFF" FontWeight="Bold" FontSize="12" BorderThickness="0"/>
            </Border>
            <Border CornerRadius="4" Grid.Column="2">
                <Button x:Name="BtnCancel" Content="CANCEL" Height="38" Background="#475569" Foreground="#FFFFFF" FontWeight="Bold" FontSize="12" BorderThickness="0"/>
            </Border>
        </Grid>
    </Grid>
</Window>
'@
    $StringReader = [System.IO.StringReader]::new($BitlockerXAML)
    $XmlReader = [System.Xml.XmlReader]::Create($StringReader)
    $Win = [Windows.Markup.XamlReader]::Load($XmlReader)
    $ComboDrives = $Win.FindName("ComboDrives")
    $Key1 = $Win.FindName("Key1"); $Key2 = $Win.FindName("Key2"); $Key3 = $Win.FindName("Key3"); $Key4 = $Win.FindName("Key4")
    $Key5 = $Win.FindName("Key5"); $Key6 = $Win.FindName("Key6"); $Key7 = $Win.FindName("Key7"); $Key8 = $Win.FindName("Key8")
    $TxtStatus = $Win.FindName("TxtStatus")
    $BtnUnlock = $Win.FindName("BtnUnlock"); $BtnCancel = $Win.FindName("BtnCancel")

    # Auto-detect locked drives from manage-bde output
    $lockedDrives = @()
    try {
        $bdeRaw = manage-bde -status 2>$null
        $currentLetter = $null
        foreach ($line in $bdeRaw) {
            if ($line -match '^.*Volume\s+([A-Z]):') {
                $currentLetter = $Matches[1]
            } elseif ($line -match 'Lock Status:\s+Locked') {
                if ($currentLetter) { $lockedDrives += $currentLetter }
            }
        }
    } catch {}
    if ($lockedDrives.Count -eq 0) {
        $ComboDrives.Items.Add("(No locked drives detected)")
        $TxtStatus.Text = "Status: [!] No BitLocker locked drives found"
        $TxtStatus.Foreground = [System.Windows.Media.Brushes]::Yellow
    } else {
        $lockedDrives | ForEach-Object { $ComboDrives.Items.Add("$($_): [LOCKED]") }
        $ComboDrives.SelectedIndex = 0
    }

    # Independent TextBox handling (auto-advance + backspace)
    $keyBoxes = @($Key1, $Key2, $Key3, $Key4, $Key5, $Key6, $Key7, $Key8)

    function Register-AutoAdvance([object]$Box, [object]$NextBox) {
        $Box.Add_TextChanged({
            if ($Box.Text.Length -eq 6) { $NextBox.Focus() | Out-Null }
        })
    }
    for ($i = 0; $i -lt 7; $i++) { Register-AutoAdvance $keyBoxes[$i] $keyBoxes[$i + 1] }

    function Register-Backspace([object]$Box, [object]$PrevBox) {
        $Box.Add_PreviewKeyDown({
            param($s, $e)
            if ($e.Key -eq [System.Windows.Input.Key]::Back -and $Box.Text.Length -eq 0) {
                $PrevBox.Focus() | Out-Null; $e.Handled = $true
            }
        })
    }
    for ($i = 1; $i -lt 8; $i++) { Register-Backspace $keyBoxes[$i] $keyBoxes[$i - 1] }

    # Paste handler: distribute full key across all boxes
    function Register-Paste([object]$Box) {
        $Box.Add_PreviewExecuted({
            param($s, $e)
            if ($e.Command -eq [System.Windows.Input.ApplicationCommands]::Paste) {
                $e.Handled = $true
                $clipText = [System.Windows.Clipboard]::GetText() -replace '[^0-9]', ''
                if ($clipText.Length -gt 0) {
                    for ($j = 0; $j -lt 8; $j++) {
                        $start = $j * 6
                        if ($start -ge $clipText.Length) { $keyBoxes[$j].Clear(); continue }
                        $len = [Math]::Min(6, $clipText.Length - $start)
                        $keyBoxes[$j].Text = $clipText.Substring($start, $len)
                    }
                    ($keyBoxes | Where-Object { $_.Text.Length -lt 6 } | Select-Object -First 1).Focus() | Out-Null
                }
            }
        })
    }
    $keyBoxes | ForEach-Object { Register-Paste $_ }

    # Unlock logic
    $BtnUnlock.Add_Click({
        $fullKey = ""
        $valid = $true
        foreach ($box in $keyBoxes) {
            $segment = $box.Text -replace '[^0-9]', ''
            if ($segment.Length -ne 6) { $valid = $false; break }
            if ($fullKey -ne "") { $fullKey += "-" }
            $fullKey += $segment
        }
        if (-not $valid -or $fullKey.Length -ne 55) {
            $TxtStatus.Text = "Status: [!] Enter complete 48-digit recovery key"
            $TxtStatus.Foreground = [System.Windows.Media.Brushes]::Red
            return
        }

        $TxtStatus.Text = "Status: [..] Decrypting drive..."
        $TxtStatus.Foreground = [System.Windows.Media.Brushes]::Yellow
        [System.Windows.Forms.Application]::DoEvents()

        $targetDrive = ($ComboDrives.SelectedItem -replace ':.*', '') -replace '\s', ''
        $digitsOnly = $fullKey -replace '[^0-9]', ''
        manage-bde -unlock "$($targetDrive):" -RecoveryPassword $digitsOnly 2>$null | Out-Null

        $check = manage-bde -status "$($targetDrive):" 2>$null | Out-String
        if ($check -match "Lock Status:\s+Unlocked" -or $LASTEXITCODE -eq 0) {
            $global:BitLockerState = "Unlocked"; $global:HasBitLocker = $false
            $TxtStatus.Text = "Status: [OK] Decryption successful"
            $TxtStatus.Foreground = [System.Windows.Media.Brushes]::LightGreen
            Start-Sleep -Seconds 1
            $Win.Close()
        } else {
            $TxtStatus.Text = "Status: [FAIL] Invalid recovery key. Try again"
            $TxtStatus.Foreground = [System.Windows.Media.Brushes]::Red
        }
    })

    $BtnCancel.Add_Click({ $Win.Close() })
    $Win.ShowDialog() | Out-Null
    Refresh-Hardware-Specs
}

# ==============================================================================
# MODULE 2: WIFI WPF DIALOG
# Fully replaces the old console-based Invoke-WifiConnect.
# XAML window: scan list + SSID/password fields + show-password toggle.
# Status feedback via inline TextBlock.
# ==============================================================================
function Invoke-WifiConnect {
    if ($global:WifiDialogOpen) { return }
    $global:WifiDialogOpen = $true
    $WifiXAML = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Wireless Network Connector" Width="560" Height="400"
        Background="#0F172A" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" ShowInTaskbar="False">
    <Window.Resources>
        <Style TargetType="Label">
            <Setter Property="Foreground" Value="#94A3B8"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="FontSize" Value="11"/>
        </Style>
    </Window.Resources>
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Text="WIRELESS NETWORK CONNECTOR" FontSize="14" FontWeight="Bold" Foreground="#38BDF8"/>
        <Rectangle Grid.Row="0" Height="2" Fill="#334155" Margin="0,25,0,0"/>

        <Grid Grid.Row="1" Margin="0,10,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="15"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <Grid Grid.Column="0">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <TextBlock Grid.Row="0" Text="AVAILABLE NETWORKS:" Foreground="#94A3B8" FontWeight="Bold" FontSize="11"/>
                <ListBox x:Name="ListNetworks" Grid.Row="1" Background="#1E293B" Foreground="#FFFFFF" BorderBrush="#475569" Margin="0,5,0,5" FontSize="13"/>
                <Button x:Name="BtnScan" Grid.Row="2" Content="  SCAN NETWORKS" Height="32" Background="#3B82F6" Foreground="#FFFFFF" FontWeight="Bold" FontSize="11" BorderThickness="0" HorizontalContentAlignment="Center"/>
            </Grid>

            <Grid Grid.Column="2">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <TextBlock Grid.Row="0" Text="SELECTED NETWORK:" Foreground="#94A3B8" FontWeight="Bold" FontSize="11"/>
                <StackPanel Grid.Row="1" Margin="0,10,0,0">
                    <Label Content="SSID:"/>
                    <TextBox x:Name="TxtSSID" Height="30" Background="#1E293B" Foreground="#FFFFFF" BorderBrush="#475569" FontSize="13"/>
                </StackPanel>
                <StackPanel Grid.Row="2" Margin="0,10,0,0">
                    <Label Content="PASSWORD:"/>
                    <Grid>
                        <PasswordBox x:Name="PassHidden" Height="30" Background="#1E293B" Foreground="#FFFFFF" BorderBrush="#475569" FontSize="13"/>
                        <TextBox x:Name="PassVisible" Height="30" Background="#1E293B" Foreground="#FFFFFF" BorderBrush="#475569" FontSize="13" Visibility="Hidden"/>
                    </Grid>
                </StackPanel>
                <CheckBox x:Name="ChkShowPass" Grid.Row="3" Content="  Show Password" Foreground="#94A3B8" FontSize="11" Margin="0,8,0,0"/>
            </Grid>
        </Grid>

        <TextBlock x:Name="TxtStatus" Grid.Row="2" Text="Status: Ready" Foreground="#475569" FontSize="11" Margin="0,10,0,0"/>

        <Grid Grid.Row="3" Margin="0,10,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="10"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Border CornerRadius="4" Grid.Column="0">
                <Button x:Name="BtnConnect" Content="CONNECT" Height="38" Background="#10B981" Foreground="#FFFFFF" FontWeight="Bold" FontSize="12" BorderThickness="0"/>
            </Border>
            <Border CornerRadius="4" Grid.Column="2">
                <Button x:Name="BtnCancel" Content="CANCEL" Height="38" Background="#475569" Foreground="#FFFFFF" FontWeight="Bold" FontSize="12" BorderThickness="0"/>
            </Border>
        </Grid>
    </Grid>
</Window>
'@
    $StringReader = [System.IO.StringReader]::new($WifiXAML)
    $XmlReader = [System.Xml.XmlReader]::Create($StringReader)
    $Win = [Windows.Markup.XamlReader]::Load($XmlReader)
    $ListNetworks = $Win.FindName("ListNetworks")
    $TxtSSID = $Win.FindName("TxtSSID")
    $PassHidden = $Win.FindName("PassHidden"); $PassVisible = $Win.FindName("PassVisible")
    $ChkShowPass = $Win.FindName("ChkShowPass")
    $TxtStatus = $Win.FindName("TxtStatus")
    $BtnScan = $Win.FindName("BtnScan"); $BtnConnect = $Win.FindName("BtnConnect"); $BtnCancel = $Win.FindName("BtnCancel")

    $global:scanLock = $false
    $scanNetworks = {
        if ($global:scanLock) { return }
        $global:scanLock = $true
        $ListNetworks.Items.Clear()
        $TxtStatus.Text = "Status: Scanning..."
        $TxtStatus.Foreground = [System.Windows.Media.Brushes]::Yellow
        [System.Windows.Forms.Application]::DoEvents()

        net start wlansvc 2>$null | Out-Null
        Start-Sleep -Seconds 2
        netsh wlan scan 2>$null | Out-Null
        Start-Sleep -Seconds 3

        $output = netsh wlan show networks mode=bssid 2>$null
        $ssids = @()
        if ($output) {
            foreach ($line in $output) {
                if ($line -match '^\s*SSID\s+\d+\s+:\s+(.+)') {
                    $ssid = $Matches[1].Trim()
                    if ($ssid -ne "" -and $ssid -notmatch '^[0-9a-fA-F:]{17}$') {
                        $ssids += $ssid
                    }
                }
            }
        }
        if ($ssids.Count -eq 0) {
            $adapter = netsh wlan show interfaces 2>$null
            if (-not $adapter) {
                $TxtStatus.Text = "Status: [!] No wireless adapter detected"
            } else {
                $TxtStatus.Text = "Status: [!] No networks found"
            }
            $TxtStatus.Foreground = [System.Windows.Media.Brushes]::Red
        } else {
            $ssids = $ssids | Sort-Object -Unique
            $ssids | ForEach-Object { $ListNetworks.Items.Add($_) }
            $count = $ListNetworks.Items.Count
            $statusSuffix = if ($count -ne 1) { 's' } else { '' }
            $TxtStatus.Text = "Status: $count network$statusSuffix found"
            $TxtStatus.Foreground = [System.Windows.Media.Brushes]::LightGreen
        }
        $global:scanLock = $false
    }
    & $scanNetworks

    # Show Password toggle
    $ChkShowPass.Add_Checked({
        $PassVisible.Text = $PassHidden.Password
        $PassHidden.Visibility = "Hidden"
        $PassVisible.Visibility = "Visible"
    })
    $ChkShowPass.Add_Unchecked({
        $PassHidden.Password = $PassVisible.Text
        $PassVisible.Visibility = "Hidden"
        $PassHidden.Visibility = "Visible"
    })

    # ListBox selection → auto-fill SSID
    $ListNetworks.Add_SelectionChanged({
        if ($ListNetworks.SelectedItem -ne $null) {
            $TxtSSID.Text = $ListNetworks.SelectedItem.ToString()
        }
    })

    # Scan button
    $BtnScan.Add_Click($scanNetworks)

    # Connect logic
    $BtnConnect.Add_Click({
        $ssid = $TxtSSID.Text.Trim()
        $password = if ($ChkShowPass.IsChecked -eq $true) { $PassVisible.Text } else { $PassHidden.Password }
        if ($ssid -eq "") {
            $TxtStatus.Text = "Status: [!] Please enter or select an SSID"
            $TxtStatus.Foreground = [System.Windows.Media.Brushes]::Red
            return
        }
        if ($password.Length -lt 6) {
            $TxtStatus.Text = "Status: [!] Password must be at least 6 characters"
            $TxtStatus.Foreground = [System.Windows.Media.Brushes]::Red
            return
        }

        $TxtStatus.Text = "Status: [..] Connecting to [$ssid]..."
        $TxtStatus.Foreground = [System.Windows.Media.Brushes]::Yellow
        [System.Windows.Forms.Application]::DoEvents()

        $WlanXml = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$ssid</name>
    <SSIDConfig><SSID><name>$ssid</name></SSID></SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption><authentication>WPA2PSK</authentication><encryption>AES</encryption><useOneX>false</useOneX></authEncryption>
            <sharedKey><keyType>passPhrase</keyType><protected>false</protected><keyMaterial>$password</keyMaterial></sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@
        $TempPath = "X:\TempWifiProfile.xml"
        try {
            $WlanXml | Set-Content -Path $TempPath -Force
            netsh wlan add profile filename=$TempPath user=all 2>&1 | Out-Null
            netsh wlan connect name="$ssid" 2>&1 | Out-Null
            Start-Sleep -Seconds 3

            $network = Get-CimInstance Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -ne $null }
            if ($network) {
                $ip = $network.IPAddress[0]
                $global:HasInternet = $true
                $TxtStatus.Text = "Status: [OK] Connected - IP: $ip"
                $TxtStatus.Foreground = [System.Windows.Media.Brushes]::LightGreen
                Start-Sleep -Seconds 2
                $Win.Close()
            } else {
                $TxtStatus.Text = "Status: [FAIL] Connection failed. Check SSID and password"
                $TxtStatus.Foreground = [System.Windows.Media.Brushes]::Red
            }
        } catch {
            $TxtStatus.Text = "Status: [FAIL] Error: $_"
            $TxtStatus.Foreground = [System.Windows.Media.Brushes]::Red
        } finally {
            if (Test-Path $TempPath) { Remove-Item $TempPath -Force -ErrorAction SilentlyContinue }
        }
    })

    $BtnCancel.Add_Click({ $Win.Close() })
    try { $Win.ShowDialog() | Out-Null } finally { $global:WifiDialogOpen = $false }
    Refresh-Hardware-Specs
}

# ==============================================================================
# MODULE: OS PARAMETER CONFIGURATOR
# ==============================================================================
function Invoke-OSSelection {
    $OSSelectXAML = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="CoreSystem - Parameter Configurator" Width="740" Height="360"
        Background="#0F172A" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" ShowInTaskbar="False">
    <Window.Resources>
        <Style TargetType="Label">
            <Setter Property="Foreground" Value="#38BDF8"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Margin" Value="0,0,0,5"/>
        </Style>
        <Style x:Key="ExecButton" TargetType="Button">
            <Setter Property="Background" Value="#10B981"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Height" Value="46"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="FontSize" Value="14"/>
        </Style>
    </Window.Resources>
    <Grid Margin="20">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Margin="0,0,0,15">
            <TextBlock x:Name="TxtSubTitle" Text="DEPLOYMENT PARAMS CONFIGURATOR" FontSize="14" FontWeight="Bold" Foreground="#38BDF8"/>
            <Rectangle Height="2" Fill="#334155" Margin="0,5,0,0"/>
        </StackPanel>

        <Grid Grid.Row="1" VerticalAlignment="Center">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="20"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="15"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <StackPanel Grid.Row="0" Grid.Column="0">
                <Label Content="1. TARGET OPERATING SYSTEM:"/>
                <ComboBox x:Name="ComboOS" Height="34" FontSize="13" Background="#1E293B" Foreground="#000000" FontWeight="Bold" Padding="6,4,0,0"/>
            </StackPanel>
            <StackPanel Grid.Row="0" Grid.Column="2">
                <Label Content="2. OS EDITION:"/>
                <ComboBox x:Name="ComboEdition" Height="34" FontSize="13" Background="#1E293B" Foreground="#000000" FontWeight="Bold" Padding="6,4,0,0"/>
            </StackPanel>
            <StackPanel Grid.Row="2" Grid.Column="0">
                <Label Content="3. LANGUAGE CODE:"/>
                <ComboBox x:Name="ComboLang" Height="34" FontSize="13" Background="#1E293B" Foreground="#000000" FontWeight="Bold" Padding="6,4,0,0"/>
            </StackPanel>
            <StackPanel Grid.Row="2" Grid.Column="2">
                <Label Content="4. ACTIVATION METHOD:"/>
                <ComboBox x:Name="ComboActivation" Height="34" FontSize="13" Background="#1E293B" Foreground="#000000" FontWeight="Bold" Padding="6,4,0,0"/>
            </StackPanel>
        </Grid>

        <Grid Grid.Row="2" Margin="0,20,0,0">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" VerticalAlignment="Center">
                <TextBlock Text="WORKFLOW: OSDCloudCLI" FontSize="11" FontWeight="Bold" Foreground="#64748B"/>
                <TextBlock x:Name="TxtMatchedFiles" Text="Detecting Script Mapping..." FontSize="10" Foreground="#A8A29E" Margin="0,2,0,0"/>
            </StackPanel>
            <Border CornerRadius="6" Grid.Column="1" Width="240">
                <Button x:Name="BtnExecuteCLI" Content="START OS DEPLOYMENT" Style="{StaticResource ExecButton}"/>
            </Border>
        </Grid>
    </Grid>
</Window>
'@

    $StringReader = [System.IO.StringReader]::new($OSSelectXAML)
    $XmlReader = [System.Xml.XmlReader]::Create($StringReader)
    $SubWindow = [Windows.Markup.XamlReader]::Load($XmlReader)

    $ComboOS         = $SubWindow.FindName("ComboOS")
    $ComboEdition    = $SubWindow.FindName("ComboEdition")
    $ComboLang       = $SubWindow.FindName("ComboLang")
    $ComboActivation = $SubWindow.FindName("ComboActivation")
    $BtnExecuteCLI   = $SubWindow.FindName("BtnExecuteCLI")
    $TxtSubTitle     = $SubWindow.FindName("TxtSubTitle")
    $TxtMatchedFiles = $SubWindow.FindName("TxtMatchedFiles")

    switch ($global:DeployMode) {
        "Vanilla" {
            $TxtSubTitle.Text = "DEPLOYMENT TASK: VANILLA OS [ FLOW 1 ]"
            $TxtMatchedFiles.Text = "Mode: Pure Microsoft Clean Install (No Injections)"
        }
        "TweaksOnly" {
            $TxtSubTitle.Text = "DEPLOYMENT TASK: BUSINESS TWEAKS ONLY [ FLOW 2 ]"
            $TxtMatchedFiles.Text = "Profile Strategy: Modular Next-Step Tweaks Deployment"
        }
        "TweaksApps" {
            $TxtSubTitle.Text = "DEPLOYMENT TASK: TWEAKS + APPLICATIONS [ FLOW 3 ]"
            $TxtMatchedFiles.Text = "Profile Strategy: Modular Next-Step Combination Deployment"
        }
    }

    if (Test-Path $global:OsdCloudJsonPath) {
        $global:ConfigData = Get-Content $global:OsdCloudJsonPath -Raw | ConvertFrom-Json
        foreach ($val in $global:ConfigData.OperatingSystem.values) { [void]$ComboOS.Items.Add($val) }
        $ComboOS.SelectedItem = $global:ConfigData.OperatingSystem.default
        foreach ($val in $global:ConfigData.OSLanguageCode.values) { [void]$ComboLang.Items.Add($val) }
        $ComboLang.SelectedItem = $global:ConfigData.OSLanguageCode.default
        foreach ($val in $global:ConfigData.OSActivation.values) { [void]$ComboActivation.Items.Add($val) }
        $ComboActivation.SelectedItem = $global:ConfigData.OSActivation.default
        foreach ($item in $global:ConfigData.OSEdition.values) { [void]$ComboEdition.Items.Add($item.Edition) }
        $ComboEdition.SelectedItem = $global:ConfigData.OSEdition.default
    }

    $EditionChangeAction = {
        $SelectedEdition = $ComboEdition.SelectedItem
        if ($null -eq $SelectedEdition) { return }
        if ($SelectedEdition -match "Enterprise|Education") {
            $ComboActivation.Items.Clear()
            [void]$ComboActivation.Items.Add("Volume")
            $ComboActivation.SelectedItem = "Volume"
            $ComboActivation.IsEnabled = $false
        } elseif ($SelectedEdition -match "Home") {
            $ComboActivation.Items.Clear()
            [void]$ComboActivation.Items.Add("Retail")
            $ComboActivation.SelectedItem = "Retail"
            $ComboActivation.IsEnabled = $false
        } else {
            $ComboActivation.Items.Clear()
            if ($global:ConfigData -ne $null) {
                foreach ($val in $global:ConfigData.OSActivation.values) { [void]$ComboActivation.Items.Add($val) }
            }
            $ComboActivation.SelectedItem = "Volume"
            $ComboActivation.IsEnabled = $true
        }
    }
    $ComboEdition.add_SelectionChanged($EditionChangeAction)
    & $EditionChangeAction

    $BtnExecuteCLI.add_Click({
        $global:ConfigData.OperatingSystem.default = $ComboOS.SelectedItem
        $global:ConfigData.OSActivation.default    = $ComboActivation.SelectedItem
        $global:ConfigData.OSLanguageCode.default  = $ComboLang.SelectedItem
        $global:ConfigData.OSEdition.default       = $ComboEdition.SelectedItem

        $global:ConfigData | Add-Member -MemberType NoteProperty -Name "Unattend" -Value $null -Force
        $global:ConfigData | Add-Member -MemberType NoteProperty -Name "PostSetupScript" -Value $null -Force

        $global:ConfigData | ConvertTo-Json -Depth 10 | Set-Content -Path $global:OsdCloudJsonPath -Force
        $global:ConfirmDeploy = $true
        $SubWindow.Close()
    })

    $SubWindow.ShowDialog() | Out-Null
}

# ==============================================================================
# MODULE 3: DEPLOYMENT PROGRESS WPF DIALOG
# XAML window wrapping the OSDCloudCLI console output.
# Console positioned via WinAPI (independent top-level window, no SetParent).
# Info panel shows OS, Edition, Language, Activation, Task, Elapsed time.
# MainWindow is hidden during deployment to avoid Z-order conflicts.
# ==============================================================================
function Invoke-DeploymentProgress {
    $DeployProgressXAML = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="CoreSystem - OS Deployment" Width="800" Height="620"
        Background="#0F172A" WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        ShowInTaskbar="False">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Title Bar Area -->
        <Border Grid.Row="0" Background="#0F172A" BorderBrush="#1E293B" BorderThickness="0,0,0,1" Padding="0,0,0,0" Height="40">
            <Grid Margin="15,0,15,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" Text="CORESYSTEM" Foreground="#38BDF8" FontSize="16" FontWeight="Bold" VerticalAlignment="Center"/>
                <TextBlock Grid.Column="1" Text="OS DEPLOYMENT IN PROGRESS" Foreground="#FFFFFF" FontSize="13" FontWeight="Bold" VerticalAlignment="Center" Margin="10,0,0,0"/>
                <Border Grid.Column="2" Background="#10B981" CornerRadius="3" Padding="8,3,8,3" VerticalAlignment="Center">
                    <TextBlock Text="STATUS: DEPLOYING" Foreground="#FFFFFF" FontSize="10" FontWeight="Bold"/>
                </Border>
            </Grid>
        </Border>

        <!-- Console Area -->
        <Border Grid.Row="1" Background="#0C0C19" BorderBrush="#334155" BorderThickness="1" Margin="15,10,15,10">
            <!-- Console is positioned here via WinAPI -->
        </Border>

        <!-- Info Footer -->
        <Border Grid.Row="2" Background="#1E293B" BorderBrush="#334155" BorderThickness="0,1,0,0" Padding="15,10,15,10">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <TextBlock Grid.Row="0" Grid.Column="0" Text="OS:" Foreground="#64748B" FontWeight="Bold" FontSize="11"/>
                <TextBlock Grid.Row="0" Grid.Column="1" x:Name="TxtOS" Text="..." Foreground="#FFFFFF" FontSize="11" Margin="5,0,15,0"/>

                <TextBlock Grid.Row="0" Grid.Column="2" Text="Edition:" Foreground="#64748B" FontWeight="Bold" FontSize="11"/>
                <TextBlock Grid.Row="0" Grid.Column="3" x:Name="TxtEdition" Text="..." Foreground="#FFFFFF" FontSize="11" Margin="5,0,15,0"/>

                <TextBlock Grid.Row="0" Grid.Column="4" Text="Lang:" Foreground="#64748B" FontWeight="Bold" FontSize="11"/>
                <TextBlock Grid.Row="0" Grid.Column="5" x:Name="TxtLang" Text="..." Foreground="#FFFFFF" FontSize="11" Margin="5,0,0,0"/>

                <TextBlock Grid.Row="1" Grid.Column="0" Text="Activation:" Foreground="#64748B" FontWeight="Bold" FontSize="11"/>
                <TextBlock Grid.Row="1" Grid.Column="1" x:Name="TxtActivation" Text="..." Foreground="#FFFFFF" FontSize="11" Margin="5,0,15,0"/>

                <TextBlock Grid.Row="1" Grid.Column="2" Text="Task:" Foreground="#64748B" FontWeight="Bold" FontSize="11"/>
                <TextBlock Grid.Row="1" Grid.Column="3" x:Name="TxtTask" Text="OSDCloud SkipFirmwareUpdate" Foreground="#38BDF8" FontSize="11" Margin="5,0,15,0"/>

                <TextBlock Grid.Row="1" Grid.Column="4" Text="Elapsed:" Foreground="#64748B" FontWeight="Bold" FontSize="11"/>
                <TextBlock Grid.Row="1" Grid.Column="5" x:Name="TxtElapsed" Text="00:00:00" Foreground="#10B981" FontSize="11" FontWeight="Bold" Margin="5,0,0,0"/>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

    $StringReader = [System.IO.StringReader]::new($DeployProgressXAML)
    $XmlReader = [System.Xml.XmlReader]::Create($StringReader)
    $DeployWin = [Windows.Markup.XamlReader]::Load($XmlReader)

    $TxtOS = $DeployWin.FindName("TxtOS")
    $TxtEdition = $DeployWin.FindName("TxtEdition")
    $TxtLang = $DeployWin.FindName("TxtLang")
    $TxtActivation = $DeployWin.FindName("TxtActivation")
    $TxtTask = $DeployWin.FindName("TxtTask")
    $TxtElapsed = $DeployWin.FindName("TxtElapsed")

    # Populate info from saved config
    if ($global:ConfigData) {
        if ($global:ConfigData.OperatingSystem) { $TxtOS.Text = $global:ConfigData.OperatingSystem.default }
        if ($global:ConfigData.OSEdition) { $TxtEdition.Text = $global:ConfigData.OSEdition.default }
        if ($global:ConfigData.OSLanguageCode) { $TxtLang.Text = $global:ConfigData.OSLanguageCode.default }
        if ($global:ConfigData.OSActivation) { $TxtActivation.Text = $global:ConfigData.OSActivation.default }
    }
    # Show the dialog (non-blocking - dispatcher continues from MainWindow)
    $DeployWin.Show()
    [System.Windows.Forms.Application]::DoEvents()

    # Get XAML window bounds via GetWindowRect (reliable screen coords)
    $helper = New-Object 'System.Windows.Interop.WindowInteropHelper' -ArgumentList $DeployWin
    $hWndDeploy = $helper.Handle

    $wRect = New-Object RECT
    $cRect = New-Object RECT
    [WinPEConsole]::GetWindowRect($hWndDeploy, [ref]$wRect) | Out-Null
    [WinPEConsole]::GetClientRect($hWndDeploy, [ref]$cRect) | Out-Null

    # Non-client offsets (title bar + border width)
    $cPoint = New-Object POINT
    $csOk = [WinPEConsole]::ClientToScreen($hWndDeploy, [ref]$cPoint)
    if ($csOk) { $ncOffX = $cPoint.X - $wRect.Left; $ncOffY = $cPoint.Y - $wRect.Top }
    else       { $ncOffX = 8; $ncOffY = 31 }  # fallback: Win10 default

    # XAML layout inside client area:
    #   Grid.Row=0 (header):     Height=40
    #   Border Margin:           Top=10, Left=15, Right=15, Bottom=10
    #   Console within Border:   Inner area
    $borderLeft = 16; $borderTop = 52
    $borderWidth  = ($cRect.Right - $cRect.Left) - 32
    $borderHeight = ($cRect.Bottom - $cRect.Top) - 155

    # Console screen position
    $consoleScreenX = $wRect.Left + $ncOffX + $borderLeft
    $consoleScreenY = $wRect.Top  + $ncOffY + $borderTop
    $consoleWidth   = [Math]::Max(200, $borderWidth)
    $consoleHeight  = [Math]::Max(100, $borderHeight)

    # Strip chrome (no caption/frame) to blend into XAML
    $GWL_STYLE = -16
    $WS_CAPTION = 0x00C00000; $WS_SYSMENU = 0x00080000
    $WS_SIZEBOX = 0x00040000; $WS_MINIMIZEBOX = 0x00020000; $WS_MAXIMIZEBOX = 0x00010000
    $currStyle = [WinPEConsole]::GetWindowLong($global:hConsole, $GWL_STYLE)
    $borderless = $currStyle -band (-bnot ($WS_CAPTION -bor $WS_SYSMENU -bor $WS_SIZEBOX -bor $WS_MINIMIZEBOX -bor $WS_MAXIMIZEBOX))
    [WinPEConsole]::SetWindowLong($global:hConsole, $GWL_STYLE, $borderless) | Out-Null
    [WinPEConsole]::SetWindowPos($global:hConsole, [IntPtr]::Zero, 0, 0, 0, 0, 0x0020 -bor 0x0002 -bor 0x0001) | Out-Null

    # Move + show at front
    [WinPEConsole]::MoveWindow($global:hConsole, $consoleScreenX, $consoleScreenY, $consoleWidth, $consoleHeight, $true) | Out-Null
    [WinPEConsole]::SetWindowPos($global:hConsole, [IntPtr]::Zero, 0, 0, 0, 0, 0x0020 -bor 0x0002 -bor 0x0001) | Out-Null
    [WinPEConsole]::ShowWindow($global:hConsole, 9) | Out-Null
    # Reset buffer to match window size (hides scrollbar that MoveWindow may introduce)
    try { $Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(90, 25); $Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size(90, 25) } catch {}

    # Run deployment inline (foreground runspace — OSDCloudCLI needs full module access)
    $global:DeployStartTime = Get-Date
    $deployTask = "OSDCloud SkipFirmwareUpdate"
    try {
        Deploy-OSDCloudCLI -Task $deployTask
    } catch {
        Write-Host "[X] PIPELINE ERROR: $_" -ForegroundColor Red
    }
    $totalTime = (Get-Date) - $global:DeployStartTime
    $TxtElapsed.Text = $totalTime.ToString('hh\:mm\:ss')

    # Post-deployment steps
    switch ($global:DeployMode) {
        "TweaksOnly" {
            Write-Host "[*] Launching deployment handler for Flow 2 [BUSINESS TWEAKS]..." -ForegroundColor Cyan
            $NextStepTweaks = "X:\Windows\System32\next-step-tweaks.ps1"
            if (Test-Path $NextStepTweaks) { & $NextStepTweaks }
            else { Write-Host "[!] Warning: $NextStepTweaks not found!" -ForegroundColor Yellow }
        }
        "TweaksApps" {
            Write-Host "[*] Launching deployment handler for Flow 3 [TWEAKS + APPS]..." -ForegroundColor Green
            $NextStepCombo = "X:\Windows\System32\next-step-combo.ps1"
            if (Test-Path $NextStepCombo) { & $NextStepCombo }
            else { Write-Host "[!] Warning: $NextStepCombo not found!" -ForegroundColor Yellow }
        }
        "Vanilla" {
            Write-Host "[*] Flow 1 Detected: Skipping profile injection (Vanilla OS Mode)." -ForegroundColor Gray
        }
    }

    # Cleanup
    $DeployWin.Close()
    Set-ConsoleState -Mode "Hide"
    wpeutil reboot
}

# ==============================================================================
# MODULE 4: EXECUTE-DEPLOYMENTPIPELINE
# Flow: OSConfigurator → Hide MainWindow → DeploymentProgress WPF → Deploy-OSDCloudCLI
# MainWindow is hidden so the deployment dialog stays visually on top.
# ==============================================================================
function Execute-DeploymentPipeline {
    Invoke-OSSelection
    if ($global:ConfirmDeploy -eq $true) {
        $global:Form.Hide()
        try {
            Invoke-DeploymentProgress
        } catch {
            $global:Form.Show()
            throw
        }
    }
}

# ==============================================================================
# MAIN WINDOW DEFINITION (identical layout to original coresystem.ps1)
# ==============================================================================
$MainWindowXAML = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="CORESYSTEM | ADVANCED WINDOWS DEPLOYMENT SYSTEM"
        Width="840" Height="520" Background="#0F172A"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize">
    <Window.Resources>
        <Style x:Key="GroupPanel" TargetType="GroupBox">
            <Setter Property="BorderBrush" Value="#334155"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Foreground" Value="#94A3B8"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Margin" Value="0,0,0,10"/>
        </Style>
        <Style x:Key="LauncherButton" TargetType="Button">
            <Setter Property="Background" Value="#1E293B"/>
            <Setter Property="BorderBrush" Value="#475569"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Height" Value="40"/>
            <Setter Property="Margin" Value="0,0,0,4"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="4">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid Margin="15">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="5.5*"/>
            <ColumnDefinition Width="15"/>
            <ColumnDefinition Width="4.5*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="50"/>
        </Grid.RowDefinitions>

        <Grid Grid.Column="0" Grid.Row="0">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <GroupBox Grid.Row="0" Header="SYSTEM INFORMATION" Style="{StaticResource GroupPanel}">
                <Grid Margin="12" Height="165">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" x:Name="txtSecuritySpecs" Text="Boot: [Scanning]  |  SB: [Scanning]  |  TPM: [Scanning]" Foreground="#38BDF8" FontWeight="Bold" FontSize="12" VerticalAlignment="Center"/>
                    <TextBlock Grid.Row="1" x:Name="txtCPU" Text="CPU : Scanning Hardware Engine..." Foreground="#FFFFFF" FontSize="12" VerticalAlignment="Center"/>
                    <TextBlock Grid.Row="2" x:Name="txtRAM" Text="RAM : Mapping Physical Blocks..." Foreground="#FFFFFF" FontSize="12" VerticalAlignment="Center"/>
                    <TextBlock Grid.Row="3" x:Name="txtDisk" Text="Disk: Evaluating Connected Storages..." Foreground="#FFFFFF" FontSize="12" VerticalAlignment="Center"/>
                    <TextBlock Grid.Row="4" x:Name="txtBitLocker" Text="BitLocker: Initializing..." Foreground="#FFFFFF" FontSize="12" VerticalAlignment="Center"/>
                    <TextBlock Grid.Row="5" x:Name="txtIP" Text="Net : Mapping dynamic addresses..." Foreground="#FFFFFF" FontSize="12" VerticalAlignment="Center"/>
                </Grid>
            </GroupBox>

            <GroupBox Grid.Row="1" Header="SYSTEM RESCUE TOOLS" Style="{StaticResource GroupPanel}">
                <Grid Margin="10" VerticalAlignment="Center">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="10"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="8"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <Button x:Name="btnMultiDrive" Grid.Row="0" Grid.Column="0" Style="{StaticResource LauncherButton}">
                        <StackPanel Orientation="Horizontal">
                            <Border Background="#EC4899" Padding="6,2" CornerRadius="3" Margin="5,0,8,0"><TextBlock Text=" F7 " FontWeight="Bold" Foreground="White"/></Border>
                            <TextBlock Text="DISK BACKUP" VerticalAlignment="Center" FontWeight="Bold" FontSize="11"/>
                        </StackPanel>
                    </Button>

                    <Button x:Name="btnExplorer" Grid.Row="0" Grid.Column="2" Style="{StaticResource LauncherButton}">
                        <StackPanel Orientation="Horizontal">
                            <Border Background="#14B8A6" Padding="6,2" CornerRadius="3" Margin="5,0,8,0"><TextBlock Text=" F8 " FontWeight="Bold" Foreground="White"/></Border>
                            <TextBlock Text="FILE EXPLORER" VerticalAlignment="Center" FontWeight="Bold" FontSize="11"/>
                        </StackPanel>
                    </Button>

                    <Button x:Name="btnHWInfo" Grid.Row="2" Grid.Column="0" Style="{StaticResource LauncherButton}">
                        <StackPanel Orientation="Horizontal">
                            <Border Background="#E11D48" Padding="6,2" CornerRadius="3" Margin="5,0,8,0"><TextBlock Text=" F9 " FontWeight="Bold" Foreground="White"/></Border>
                            <TextBlock Text="HARDWARE INFO" VerticalAlignment="Center" FontWeight="Bold" FontSize="11"/>
                        </StackPanel>
                    </Button>

                    <Button x:Name="btnBrowser" Grid.Row="2" Grid.Column="2" Style="{StaticResource LauncherButton}">
                        <StackPanel Orientation="Horizontal">
                            <Border Background="#3B82F6" Padding="4,2" CornerRadius="3" Margin="5,0,8,0"><TextBlock Text=" F10 " FontWeight="Bold" Foreground="White"/></Border>
                            <TextBlock Text="WEB BROWSER" VerticalAlignment="Center" FontWeight="Bold" FontSize="11"/>
                        </StackPanel>
                    </Button>
                </Grid>
            </GroupBox>
        </Grid>

        <GroupBox Grid.Column="2" Grid.Row="0" Header="ADVANCED WINDOWS DEPLOYMENT" Style="{StaticResource GroupPanel}">
            <Grid Margin="10">
                <Grid.RowDefinitions>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <Button x:Name="btnFlow1" Grid.Row="0" Style="{StaticResource LauncherButton}" Height="76" VerticalAlignment="Center">
                    <StackPanel Orientation="Horizontal">
                        <Border Background="#0284C7" Padding="14,0" CornerRadius="4" Margin="5,0,12,0" Height="44"><TextBlock Text=" 1 " FontWeight="Bold" FontSize="16" Foreground="White" VerticalAlignment="Center"/></Border>
                        <StackPanel VerticalAlignment="Center">
                            <TextBlock Text="SETUP WINDOWS [DEFAULT]" FontWeight="Bold" Foreground="#FFFFFF" FontSize="12.5"/>
                            <TextBlock Text="Clean install Windows operating system" FontSize="10" Foreground="#64748B" Margin="0,1,0,0"/>
                        </StackPanel>
                    </StackPanel>
                </Button>

                <Button x:Name="btnFlow2" Grid.Row="1" Style="{StaticResource LauncherButton}" Height="76" VerticalAlignment="Center">
                    <StackPanel Orientation="Horizontal">
                        <Border Background="#F59E0B" Padding="14,0" CornerRadius="4" Margin="5,0,12,0" Height="44"><TextBlock Text=" 2 " FontWeight="Bold" FontSize="16" Foreground="White" VerticalAlignment="Center"/></Border>
                        <StackPanel VerticalAlignment="Center">
                            <TextBlock Text="SETUP WINDOWS [BUSINESS TWEAKS]" FontWeight="Bold" Foreground="#FFFFFF" FontSize="12.5"/>
                            <TextBlock Text="Deploy Windows OS with business tweaks" FontSize="10" Foreground="#64748B" Margin="0,1,0,0"/>
                        </StackPanel>
                    </StackPanel>
                </Button>

                <Button x:Name="btnFlow3" Grid.Row="2" Style="{StaticResource LauncherButton}" Height="76" VerticalAlignment="Center">
                    <StackPanel Orientation="Horizontal">
                        <Border Background="#10B981" Padding="14,0" CornerRadius="4" Margin="5,0,12,0" Height="44"><TextBlock Text=" 3 " FontWeight="Bold" FontSize="16" Foreground="White" VerticalAlignment="Center"/></Border>
                        <StackPanel VerticalAlignment="Center">
                            <TextBlock Text="SETUP WINDOWS [TWEAKS + APPS]" FontWeight="Bold" Foreground="#FFFFFF" FontSize="12.5"/>
                            <TextBlock Text="Deploy Windows OS with tweaks &amp; apps" FontSize="10" Foreground="#64748B" Margin="0,1,0,0"/>
                        </StackPanel>
                    </StackPanel>
                </Button>

                <Grid Grid.Row="3" Margin="0,10,0,2">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="10"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <Button x:Name="btnAbout" Grid.Column="0" Style="{StaticResource LauncherButton}" Height="40" Margin="0">
                        <StackPanel Orientation="Horizontal">
                            <Border Background="#8B5CF6" Padding="4,2" CornerRadius="3" Margin="5,0,8,0"><TextBlock Text=" F11 " FontWeight="Bold" Foreground="White"/></Border>
                            <TextBlock Text="ABOUT" VerticalAlignment="Center" FontWeight="Bold" FontSize="11"/>
                        </StackPanel>
                    </Button>

                    <Button x:Name="btnReboot" Grid.Column="2" Style="{StaticResource LauncherButton}" Height="40" Background="#111827" BorderBrush="#EF4444" Margin="0">
                        <StackPanel Orientation="Horizontal">
                            <Border Background="#EF4444" Padding="4,2" CornerRadius="3" Margin="5,0,8,0"><TextBlock Text=" F12 " FontWeight="Bold" Foreground="White"/></Border>
                            <TextBlock Text="REBOOT SYSTEM" VerticalAlignment="Center" FontWeight="Bold" Foreground="#EF4444" FontSize="11"/>
                        </StackPanel>
                    </Button>
                </Grid>
            </Grid>
        </GroupBox>

        <Border Grid.Row="1" Grid.ColumnSpan="3" BorderBrush="#1E293B" BorderThickness="0,1,0,0" Padding="0,8,0,0">
            <Grid VerticalAlignment="Center">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <Grid Grid.Row="0">
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Left" VerticalAlignment="Center">
                        <TextBlock Text="[F1]" Foreground="Cyan" FontWeight="Bold"/>
                        <TextBlock Text=" BitLocker | " Foreground="#94A3B8"/>
                        <TextBlock Text="[F2]" Foreground="Cyan" FontWeight="Bold"/>
                        <TextBlock Text=" WiFi Link | " Foreground="#94A3B8"/>
                        <TextBlock Text="[F4]" Foreground="Cyan" FontWeight="Bold"/>
                        <TextBlock Text=" Notepad | " Foreground="#94A3B8"/>
                        <TextBlock Text="[F5]" Foreground="Cyan" FontWeight="Bold"/>
                        <TextBlock Text=" Diskpart | " Foreground="#94A3B8"/>
                        <TextBlock Text="[F6]" Foreground="Cyan" FontWeight="Bold"/>
                        <TextBlock Text=" PS Shell | " Foreground="#94A3B8"/>
                        <TextBlock Text="[F11]" Foreground="Cyan" FontWeight="Bold"/>
                        <TextBlock Text=" About | " Foreground="#94A3B8"/>
                        <TextBlock Text="[F12]" Foreground="Red" FontWeight="Bold"/>
                        <TextBlock Text=" Reboot System " Foreground="#94A3B8"/>
                    </StackPanel>
                    <TextBlock HorizontalAlignment="Right" Text="Pipeline: OSDCloud CLI" Foreground="#38BDF8" FontWeight="Bold" FontSize="11" VerticalAlignment="Center"/>
                </Grid>

                <Grid Grid.Row="1" Margin="0,5,0,0">
                    <TextBlock HorizontalAlignment="Left" Text="SYSTEM STATUS: READY" Foreground="#475569" FontSize="10" FontWeight="Bold" VerticalAlignment="Center"/>
                    <TextBlock HorizontalAlignment="Right" Text="A project by www.coresystem.vn" Foreground="#475569" FontSize="10" VerticalAlignment="Center"/>
                </Grid>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

$StringReader = [System.IO.StringReader]::new($MainWindowXAML)
$XmlReader = [System.Xml.XmlReader]::Create($StringReader)
$global:Form = [Windows.Markup.XamlReader]::Load($XmlReader)

$global:txtSecuritySpecs = $global:Form.FindName("txtSecuritySpecs")
$global:txtCPU           = $global:Form.FindName("txtCPU")
$global:txtRAM           = $global:Form.FindName("txtRAM")
$global:txtDisk          = $global:Form.FindName("txtDisk")
$global:txtBitLocker     = $global:Form.FindName("txtBitLocker")
$global:txtIP            = $global:Form.FindName("txtIP")

Set-ConsoleState -Mode "Hide"
Refresh-Hardware-Specs

# Button click mappings for deployment flow + utility launchers
$global:Form.FindName("btnFlow1").add_Click({ $global:DeployMode = "Vanilla"; Execute-DeploymentPipeline })
$global:Form.FindName("btnFlow2").add_Click({ $global:DeployMode = "TweaksOnly"; Execute-DeploymentPipeline })
$global:Form.FindName("btnFlow3").add_Click({ $global:DeployMode = "TweaksApps"; Execute-DeploymentPipeline })

$global:Form.FindName("btnMultiDrive").add_Click({ if (Test-Path "X:\Softwares\MultiDrive\MultiDrive.exe") { Start-Process "X:\Softwares\MultiDrive\MultiDrive.exe" } })
$global:Form.FindName("btnExplorer").add_Click({ if (Test-Path "X:\Softwares\Explorer++\Explorer++.exe") { Start-Process "X:\Softwares\Explorer++\Explorer++.exe" } })
$global:Form.FindName("btnHWInfo").add_Click({ if (Test-Path "X:\Softwares\HWInfo\HWINFO64.exe") { Start-Process "X:\Softwares\HWInfo\HWINFO64.exe" } })
$global:Form.FindName("btnBrowser").add_Click({ if (Test-Path "X:\Softwares\Palemoon\Palemoon.exe") { Start-Process "X:\Softwares\Palemoon\Palemoon.exe" } })
$global:Form.FindName("btnAbout").add_Click({ Invoke-AboutDialog })
$global:Form.FindName("btnReboot").add_Click({ $global:Form.Close(); Set-ConsoleState -Mode "Show"; wpeutil reboot })

# ==============================================================================
# ROUTED COMMANDS & KEY BINDINGS
# F10=Browser, F11=About, F12=Reboot via routed commands for reliable binding.
# Numeric key deployment triggers (D1/D2/D3, NumPad1/2/3) in the KeyDown handler.
# ==============================================================================
$RebootCmd = New-Object System.Windows.Input.RoutedCommand
$RebootGesture = New-Object System.Windows.Input.KeyGesture([System.Windows.Input.Key]::F12)
$RebootBinding = New-Object System.Windows.Input.KeyBinding($RebootCmd, $RebootGesture)
[void]$global:Form.InputBindings.Add($RebootBinding)
$RebootCmdBinding = New-Object System.Windows.Input.CommandBinding($RebootCmd)
$RebootCmdBinding.add_Executed({ $global:Form.Close(); Set-ConsoleState -Mode "Show"; wpeutil reboot })
[void]$global:Form.CommandBindings.Add($RebootCmdBinding)

$AboutCmd = New-Object System.Windows.Input.RoutedCommand
$AboutGesture = New-Object System.Windows.Input.KeyGesture([System.Windows.Input.Key]::F11)
$AboutBinding = New-Object System.Windows.Input.KeyBinding($AboutCmd, $AboutGesture)
[void]$global:Form.InputBindings.Add($AboutBinding)
$AboutCmdBinding = New-Object System.Windows.Input.CommandBinding($AboutCmd)
$AboutCmdBinding.add_Executed({ Invoke-AboutDialog })
[void]$global:Form.CommandBindings.Add($AboutCmdBinding)

$BrowserCmd = New-Object System.Windows.Input.RoutedCommand
$BrowserGesture = New-Object System.Windows.Input.KeyGesture([System.Windows.Input.Key]::F10)
$BrowserBinding = New-Object System.Windows.Input.KeyBinding($BrowserCmd, $BrowserGesture)
[void]$global:Form.InputBindings.Add($BrowserBinding)
$BrowserCmdBinding = New-Object System.Windows.Input.CommandBinding($BrowserCmd)
$BrowserCmdBinding.add_Executed({ if (Test-Path "X:\Softwares\Palemoon\Palemoon.exe") { Start-Process "X:\Softwares\Palemoon\Palemoon.exe" } })
[void]$global:Form.CommandBindings.Add($BrowserCmdBinding)

# Hotkeys Mappings
$global:Form.add_KeyDown({
    param($sender, $e)
    switch ($e.Key) {
        "D1" { $global:DeployMode = "Vanilla"; Execute-DeploymentPipeline }
        "NumPad1" { $global:DeployMode = "Vanilla"; Execute-DeploymentPipeline }
        "D2" { $global:DeployMode = "TweaksOnly"; Execute-DeploymentPipeline }
        "NumPad2" { $global:DeployMode = "TweaksOnly"; Execute-DeploymentPipeline }

        "D3" { $global:DeployMode = "TweaksApps"; Execute-DeploymentPipeline }
        "NumPad3" { $global:DeployMode = "TweaksApps"; Execute-DeploymentPipeline }

        "F1" { Invoke-BitLockerUnlock }
        "F2" {
                if ($global:WifiCooldown -and ((Get-Date) - $global:WifiCooldown).TotalSeconds -lt 3) { break }
                if ($global:HasInternet) {
                    $Result = [System.Windows.MessageBox]::Show("This system is already connected. Are you sure?", "Confirmation", "YesNo", "Question")
                    if ($Result -eq "Yes") { Invoke-WifiConnect }
                } else { Invoke-WifiConnect }
                $global:WifiCooldown = Get-Date
            }
        "F4" { Start-Process "notepad.exe" }
        "F5" { Start-Process "cmd.exe" -ArgumentList "/c diskpart.exe" }
        "F6" { Start-Process "powershell.exe" -ArgumentList "-NoLogo" }
        "F7" { if (Test-Path "X:\Softwares\MultiDrive\MultiDrive.exe") { Start-Process "X:\Softwares\MultiDrive\MultiDrive.exe" } }
        "F8" { if (Test-Path "X:\Softwares\Explorer++\Explorer++.exe") { Start-Process "X:\Softwares\Explorer++\Explorer++.exe" } }
        "F9" { if (Test-Path "X:\Softwares\HWInfo\HWINFO64.exe") { Start-Process "X:\Softwares\HWInfo\HWINFO64.exe" } }
    }
})

$global:Form.ShowDialog() | Out-Null
