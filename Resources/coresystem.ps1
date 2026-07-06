# ==============================================================================
#  [CORESYSTEM | ADVANCED WINDOWS OS DEPLOYMENT]
# UI Language: 100% English | Navigation: Keyboard-Driven & Mouse
# ==============================================================================

$ProgressPreference = 'SilentlyContinue'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

# 1. WINAPI THIẾT LẬP CÁC GIÁ TRỊ CONSOLE
$WinAPI_Canvas = @"
using System;
using System.Runtime.InteropServices;
public class WinPEConsole {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int nIndex);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
Add-Type -TypeDefinition $WinAPI_Canvas -ErrorAction SilentlyContinue

$global:hConsole = [WinPEConsole]::GetForegroundWindow()

# Hàm ép kích thước Console 90X25
function Set-ConsoleState {
    param (
        [string]$Mode # "Hide" hoặc "Show"
    )
    if ($global:hConsole -ne [IntPtr]::Zero) {
        if ($Mode -eq "Hide") {
            [WinPEConsole]::MoveWindow($global:hConsole, -2000, -2000, 300, 100, $true) | Out-Null
        }
        elseif ($Mode -eq "Show") {
            $ScreenWidth  = [WinPEConsole]::GetSystemMetrics(0)
            $ScreenHeight = [WinPEConsole]::GetSystemMetrics(1)

            $Width  = 760
            $Height = 460
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
# GLOBAL VARIABLES & ENTERPRISE DIRECTORY SPECIFICATION
# ------------------------------------------------------------------------------
$global:DeployMode    = "Vanilla"
$global:ConfirmDeploy = $false
$global:HasBitLocker  = $false
$global:BitLockerState = "None"
$global:ConfigData    = $null
$global:HasInternet   = $false

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
# HARDWARE MONITOR & METRIC AUDITING
# ------------------------------------------------------------------------------
function Refresh-Hardware-Specs {
    # Khởi tạo giá trị mặc định phòng trường hợp lỗi
    $BootMode = "Unknown"
    $SecureBoot = "Unknown"
    $TPMStatus = "NOT FOUND"

    # --------------------------------------------------------------------------
    # KHỐI 1: KIỂM TRA CHẾ ĐỘ BOOT
    # --------------------------------------------------------------------------
    try {
        if ($env:Firmware_Type -eq "UEFI") {
            $BootMode = "UEFI"
        } else {
            $BootMode = "Legacy"
        }
    } catch {
        $BootMode = "ERROR"
    }

    # --------------------------------------------------------------------------
    # KHỐI 2: KIỂM TRA SECURE BOOT
    # --------------------------------------------------------------------------
    try {
        if (Confirm-SecureBootUEFI -ErrorAction SilentlyContinue) {
            $SecureBoot = "ON"
        } else {
            $SecureBoot = "OFF"
        }
    } catch {
        $SecureBoot = "UNSUPPORTED"
    }

    # --------------------------------------------------------------------------
    # KHỐI 3: KIỂM TRA TPM
    # --------------------------------------------------------------------------
    try {
        $TpmWmi = Get-CimInstance -Namespace "Root\CIMv2\Security\MicrosoftTpm" -ClassName "Win32_Tpm" -ErrorAction SilentlyContinue

        if ($TpmWmi) {
            $RawVersion = $TpmWmi.SpecVersion
            if ($RawVersion -match ",") {
                $TpmVersion = $RawVersion.Split(',')[0].Trim()
            } else {
                $TpmVersion = $RawVersion
            }
            $TPMStatus = "v$TpmVersion READY"
        } else {
            $TPMStatus = "NOT FOUND"
        }
    } catch {
        $TPMStatus = "DISABLE / NONE"
    }

    $global:txtSecuritySpecs.Text = "Boot: [$BootMode]  |  SB: [$SecureBoot]  |  TPM: [$TPMStatus]"

    # Other hardware information
    #CPU
    try {
        $CPU = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue).Name.Trim()
        $global:txtCPU.Text = "CPU : $CPU"
    } catch { $global:txtCPU.Text = "CPU : Generic Processor Module" }
    
    #RAM
    try {
        $RAMBytes = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory
        $RAMGB = [Math]::Round($RAMBytes / 1GB)
        $global:txtRAM.Text = "RAM : ${RAMGB}GB "
    } catch { $global:txtRAM.Text = "RAM : 16GB Allocated Architecture" }
    
    #DISK
    try {
        $Disks = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue
        $TargetDisk = $Disks | Where-Object { $_.InterfaceType -ne "USB" -and $_.Model -notmatch "USB|TransMemory" } | Select-Object -First 1

        if (-not $TargetDisk) {
            $TargetDisk = $Disks | Select-Object -First 1
        }

        if ($TargetDisk) {
            $SizeGB = [Math]::Round($TargetDisk.Size / 1GB)
            $global:txtDisk.Text = "Disk: $($TargetDisk.Model) ($SizeGB GB)"
        } else {
            $global:txtDisk.Text = "Disk: No Target Disk Found"
        }
    } catch {
        $global:txtDisk.Text = "Disk: Target Storage Evaluation Fault"
    }
    
    #LAN/WLAN
    $global:HasInternet = $false
    try {
        $Network = Get-CimInstance Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -ne $null }
        if ($Network) {
            $IP = $Network.IPAddress[0]
            $global:HasInternet = $true
            if ($Network.Description -match "Wireless|Wi-Fi|802.11|WLAN") {
                $global:txtIP.Text = "Net : [WIFI CONNECTED] - IP: $IP"
                $global:txtIP.Foreground = [System.Windows.Media.Brushes]::LightGreen
            } else {
                $global:txtIP.Text = "Net : [LAN CONNECTED] - IP: $IP"
                $global:txtIP.Foreground = [System.Windows.Media.Brushes]::Green
            }
        } else {
            $global:txtIP.Text = "Net : [NETWORK DISCONNECTED / STANDBY]"
            $global:txtIP.Foreground = [System.Windows.Media.Brushes]::Yellow
        }
    } catch {
        $global:txtIP.Text = "Net : [IP ROUTING STANDBY MODE]"
        $global:txtIP.Foreground = [System.Windows.Media.Brushes]::Yellow
    }

    #BITLOCKER
    try {
        $BdeStatus = manage-bde -status 2>$null | Out-String
        if ($BdeStatus -match "Lock Status:\s+Locked") {
            $global:BitLockerState = "Locked"
            $global:HasBitLocker = $true
            $global:txtBitLocker.Text = "BitLocker: [ LOCKED DRIVES DETECTED ]"
            $global:txtBitLocker.Foreground = [System.Windows.Media.Brushes]::Orange
        } elseif ($BdeStatus -match "BitLocker Version") {
            $global:BitLockerState = "Unlocked"
            $global:HasBitLocker = $false
            $global:txtBitLocker.Text = "BitLocker: [ DRIVE UNLOCKED ]"
            $global:txtBitLocker.Foreground = [System.Windows.Media.Brushes]::LightGreen
        } else {
            $global:BitLockerState = "None"
            $global:HasBitLocker = $false
            $global:txtBitLocker.Text = "BitLocker: [ NO ENCRYPTED DRIVE ]"
            $global:txtBitLocker.Foreground = [System.Windows.Media.Brushes]::Gray
        }
    } catch {
        $global:BitLockerState = "None"
        $global:HasBitLocker = $false
        $global:txtBitLocker.Text = "BitLocker: [ NOT ACTIVE ]"
        $global:txtBitLocker.Foreground = [System.Windows.Media.Brushes]::Gray
    }
}

# ------------------------------------------------------------------------------
# CONSOLE RESCUE SUB-FUNCTION [BITLOCKER & WIFI]
# ------------------------------------------------------------------------------
function Invoke-BitLockerUnlock {
    try {
        $BdeCheck = manage-bde -status 2>$null | Out-String
        if ($BdeCheck -match "Lock Status:\s+Unlocked" -or ($BdeCheck -notmatch "Lock Status")) { return }
    } catch { return }

    $global:Form.Hide()
    Set-ConsoleState -Mode "Show"
    Clear-Host

    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "             CORESYSTEM - BITLOCKER DECRYPT             " -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan
    $TargetDrive = Read-Host "[->] Enter Target Drive Letter to unlock (e.g., C)"
    if ([string]::IsNullOrWhiteSpace($TargetDrive)) { Set-ConsoleState -Mode "Hide"; $global:Form.ShowDialog() | Out-Null; return }
    $TargetDrive = $TargetDrive.ToUpper().Replace(":", "")
    $RecoveryKey = Read-Host "[KEY] Enter 48-digit BitLocker Recovery Key"
    if ([string]::IsNullOrWhiteSpace($RecoveryKey)) { Set-ConsoleState -Mode "Hide"; $global:Form.ShowDialog() | Out-Null; return }

    Write-Host "`n[*] Executing native decryption matrix..." -ForegroundColor Gray
    manage-bde -unlock "$($TargetDrive):" -RecoveryPassword $RecoveryKey

    $CheckBde = manage-bde -status "$($TargetDrive):" 2>$null | Out-String
    if ($CheckBde -match "Lock Status:\s+Unlocked" -or $LASTEXITCODE -eq 0) {
        $global:BitLockerState = "Unlocked"
        $global:HasBitLocker = $false
        Write-Host "[+] SUCCESS: Partition decrypted and mounted safely." -ForegroundColor Green
        Start-Sleep -Seconds 2
    } else {
        Write-Host "[X] ERROR: Invalid authentication recovery credentials." -ForegroundColor Red
        Start-Sleep -Seconds 2
    }

    Refresh-Hardware-Specs
    Set-ConsoleState -Mode "Hide"
    $global:Form.ShowDialog() | Out-Null
}

function Invoke-WifiConnect {
    $global:Form.Hide()
    Set-ConsoleState -Mode "Show"
    Clear-Host

    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "             CORESYSTEM - WIRELESS ENGINE               " -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "[*] Activating WLAN AutoConfig Service..." -ForegroundColor Gray

    net start wlansvc 2>$null
    Start-Sleep -Seconds 1

    Write-Host "[+] Scanning available networks over the air:`n" -ForegroundColor Cyan
    netsh wlan show networks 2>$null

    Write-Host "--------------------------------------------------------" -ForegroundColor Gray
    $SSID = Read-Host "[->] Enter Wireless SSID (WiFi Name)"
    if ([string]::IsNullOrWhiteSpace($SSID)) {
        Write-Host "[!] Operation canceled by operator." -ForegroundColor Orange
        Start-Sleep -Seconds 1
        Set-ConsoleState -Mode "Hide"
        $global:Form.ShowDialog() | Out-Null
        return
    }

    $Password = Read-Host "[KEY] Enter WPA2 Pre-Shared Password"
    if ($Password.Length -lt 6) {
        [System.Windows.MessageBox]::Show("Wifi password must be at least 6 characters. Please try again.", "Password error", "OK", "Error")
        Set-ConsoleState -Mode "Hide"
        $global:Form.ShowDialog() | Out-Null
        return
    }

    Write-Host "`n[*] Packaging profile structure into secure XML block..." -ForegroundColor Gray
    $WlanXml = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$SSID</name>
    <SSIDConfig>
        <SSID>
            <name>$SSID</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$Password</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@

    $TempPath = "X:\TempWifiProfile.xml"
    $WlanXml | Set-Content -Path $TempPath -Force

    Write-Host "[*] Injecting profile node to network sub-system..." -ForegroundColor Gray
    netsh wlan add profile filename=$TempPath user=all 2>&1 | Out-Null

    Write-Host "[*] Forcing connection link with station [$SSID]..." -ForegroundColor Yellow
    
    $WifiConnected = $false
    try {
        netsh wlan connect name="$SSID" 2>&1 | Out-Null
        
        Write-Host "[*] Waiting for DHCP lease configuration..." -ForegroundColor Gray
        Start-Sleep -Seconds 3

        # Kiem tra he thong da nhan duoc IP chua
        if (Get-CimInstance Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -ne $null }) {
            $WifiConnected = $true
        }
    } catch {
        $WifiConnected = $false
    }

    if (Test-Path $TempPath) { Remove-Item $TempPath -Force -ErrorAction SilentlyContinue }

    # Canh bao nguoi dung neu ket noi that bai
    if (-not $WifiConnected) {
        [System.Windows.MessageBox]::Show(
            "Can not connect this wifi.`n`nPlease try again:`n1. Wifi name (Must be case sensitive).`n2. Wifi password.`n3. Blank space within wifi name.`n`nPlease reconnect at main interface.",
            "Could not establish wifi connection",
            "OK", 
            "Warning"
        )
    }

    Refresh-Hardware-Specs
    Set-ConsoleState -Mode "Hide"
    $global:Form.ShowDialog() | Out-Null
}

function Invoke-AboutDialog {
    [System.Windows.MessageBox]::Show("CoreSystem Advanced OS Deployment System`n`nBuilt exclusively for Enterprise Infrastructure Deployment.`nWebsite: www.coresystem.vn`nAll rights reserved.", "About CoreSystem", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
}

# ------------------------------------------------------------------------------
# SUB-GUI: PARAMETER CONFIGURATOR
# ------------------------------------------------------------------------------
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

        # Dọn dẹp cấu hình để chuyển giao hoàn toàn quyền điều khiển về cho file kịch bản next-step độc lập
        $global:ConfigData | Add-Member -MemberType NoteProperty -Name "Unattend" -Value $null -Force
        $global:ConfigData | Add-Member -MemberType NoteProperty -Name "PostSetupScript" -Value $null -Force

        $global:ConfigData | ConvertTo-Json -Depth 10 | Set-Content -Path $global:OsdCloudJsonPath -Force
        $global:ConfirmDeploy = $true
        $SubWindow.Close()
    })

    $SubWindow.ShowDialog() | Out-Null
}

# ------------------------------------------------------------------------------
# MAIN WINDOW DEFINITION
# ------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------
# [FUNCTION] DEPLOYMENT CONTROLLER
# ------------------------------------------------------------------------------
function Execute-DeploymentPipeline {
    Invoke-OSSelection
    if ($global:ConfirmDeploy -eq $true) {
        $global:Form.Close()
        
        Set-ConsoleState -Mode "Show"
        Clear-Host
        try {
            Deploy-OSDCloudCLI -Task "OSDCloud SkipFirmwareUpdate"
        } catch {
            Write-Host "[X] PIPELINE REJECTED: $_" -ForegroundColor Red
            return
        }

        # ------------------------------------------------------------------------------
        # Tách luồng gọi file next-step.ps1 ứng với từng tình huống cài đặt
        # ------------------------------------------------------------------------------
        switch ($global:DeployMode) {
            "TweaksOnly" {
                Write-Host "[*] Launching deployment handler for Flow 2 [BUSINESS TWEAKS]..." -ForegroundColor Cyan
                $NextStepTweaks = "X:\Windows\System32\next-step-tweaks.ps1"
                
                if (Test-Path $NextStepTweaks) {
                    & $NextStepTweaks
                } else {
                    Write-Host "[!] Warning: $NextStepTweaks not found!" -ForegroundColor Yellow
                }
            }
            
            "TweaksApps" {
                Write-Host "[*] Launching deployment handler for Flow 3 [TWEAKS + APPS]..." -ForegroundColor Green
                $NextStepCombo = "X:\Windows\System32\next-step-combo.ps1"
                
                if (Test-Path $NextStepCombo) {
                    & $NextStepCombo
                } else {
                    Write-Host "[!] Warning: $NextStepCombo not found!" -ForegroundColor Yellow
                }
            }
            
            "Vanilla" {
                Write-Host "[*] Flow 1 Detected: Skipping profile injection (Vanilla OS Mode)." -ForegroundColor Gray
            }
        }
        # ------------------------------------------------------------------------------

        wpeutil reboot
    }
}

# Click Mappings cho các nút cài đặt OS & tiện ích cứu hộ
$global:Form.FindName("btnFlow1").add_Click({ $global:DeployMode = "Vanilla"; Execute-DeploymentPipeline })
$global:Form.FindName("btnFlow2").add_Click({ $global:DeployMode = "TweaksOnly"; Execute-DeploymentPipeline })
$global:Form.FindName("btnFlow3").add_Click({ $global:DeployMode = "TweaksApps"; Execute-DeploymentPipeline })

$global:Form.FindName("btnMultiDrive").add_Click({ if (Test-Path "X:\Softwares\MultiDrive\MultiDrive.exe") { Start-Process "X:\Softwares\MultiDrive\MultiDrive.exe" } })
$global:Form.FindName("btnExplorer").add_Click({ if (Test-Path "X:\Softwares\Explorer++\Explorer++.exe") { Start-Process "X:\Softwares\Explorer++\Explorer++.exe" } })
$global:Form.FindName("btnHWInfo").add_Click({ if (Test-Path "X:\Softwares\HWInfo\HWINFO64.exe") { Start-Process "X:\Softwares\HWInfo\HWINFO64.exe" } })
$global:Form.FindName("btnBrowser").add_Click({ if (Test-Path "X:\Softwares\Palemoon\Palemoon.exe") { Start-Process "X:\Softwares\Palemoon\Palemoon.exe" } })

# Click Mappings cho nút About & Reboot
$global:Form.FindName("btnAbout").add_Click({ Invoke-AboutDialog })
$global:Form.FindName("btnReboot").add_Click({ $global:Form.Close(); Set-ConsoleState -Mode "Show"; wpeutil reboot })

# ==============================================================================
# THIẾT LẬP CHỨC NĂNG HOTKEY CHO ỨNG DỤNG
# ==============================================================================

# 1. Khóa phím F12 chuyên dụng để Reboot System (Ăn 100% trên máy thật)
$RebootCmd = New-Object System.Windows.Input.RoutedCommand
$RebootGesture = New-Object System.Windows.Input.KeyGesture([System.Windows.Input.Key]::F12)
$RebootBinding = New-Object System.Windows.Input.KeyBinding($RebootCmd, $RebootGesture)
[void]$global:Form.InputBindings.Add($RebootBinding)

$RebootCmdBinding = New-Object System.Windows.Input.CommandBinding($RebootCmd)
$RebootCmdBinding.add_Executed({
    $global:Form.Close()
    Set-ConsoleState -Mode "Show"
    wpeutil reboot
})
[void]$global:Form.CommandBindings.Add($RebootCmdBinding)

# 2. Khóa phím F11 gọi hộp thoại About Dialog
$AboutCmd = New-Object System.Windows.Input.RoutedCommand
$AboutGesture = New-Object System.Windows.Input.KeyGesture([System.Windows.Input.Key]::F11)
$AboutBinding = New-Object System.Windows.Input.KeyBinding($AboutCmd, $AboutGesture)
[void]$global:Form.InputBindings.Add($AboutBinding)

$AboutCmdBinding = New-Object System.Windows.Input.CommandBinding($AboutCmd)
$AboutCmdBinding.add_Executed({ Invoke-AboutDialog })
[void]$global:Form.CommandBindings.Add($AboutCmdBinding)

# 3. Khóa phím F10 kích hoạt Web Browser Palemoon
$BrowserCmd = New-Object System.Windows.Input.RoutedCommand
$BrowserGesture = New-Object System.Windows.Input.KeyGesture([System.Windows.Input.Key]::F10)
$BrowserBinding = New-Object System.Windows.Input.KeyBinding($BrowserCmd, $BrowserGesture)
[void]$global:Form.InputBindings.Add($BrowserBinding)

$BrowserCmdBinding = New-Object System.Windows.Input.CommandBinding($BrowserCmd)
$BrowserCmdBinding.add_Executed({
    if (Test-Path "X:\Softwares\Palemoon\Palemoon.exe") { Start-Process "X:\Softwares\Palemoon\Palemoon.exe" }
})
[void]$global:Form.CommandBindings.Add($BrowserCmdBinding)

# Hotkeys Mappings cho các phím điều hướng số và cứu hộ tiêu chuẩn
$global:Form.add_KeyDown({
    param($sender, $e)

    switch ($e.Key) {
        "D1" { $global:DeployMode = "Vanilla"; Execute-DeploymentPipeline }
        "NumPad1" { $global:DeployMode = "Vanilla"; Execute-DeploymentPipeline }
        "D2" { $global:DeployMode = "TweaksOnly"; Execute-DeploymentPipeline }
        "NumPad2" { $global:DeployMode = "TweaksOnly"; Execute-DeploymentPipeline }
        "D3" { $global:DeployMode = "TweaksApps"; Execute-DeploymentPipeline }
        "NumPad3" { $global:DeployMode = "TweaksApps"; Execute-DeploymentPipeline }

        "F1" { if ($global:BitLockerState -eq "Locked") { Invoke-BitLockerUnlock } }
        "F2" {
                if ($global:HasInternet) {
                    $Result = [System.Windows.MessageBox]::Show("This system is already connected. Are you sure?", "Confirmation", "YesNo", "Question")
                    if ($Result -eq "Yes") {
                        Invoke-WifiConnect
                    }
                } else {
                    Invoke-WifiConnect
                }
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
