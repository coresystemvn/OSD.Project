# ==============================================================================
# SCRIPT: post-setup-tweaks.ps1 [Part of Windows OS Deployment System]
# By: Tran Trung Truc | www.coresystem.vn
# ==============================================================================

Write-Host "=== [CoreSystem] BAT DAU QUY TRINH FINE-TUNE POST-SETUP ===" -ForegroundColor Cyan
$GlobalTimeoutSec = 300 

# Ham kiem tra ket noi Internet
function Wait-ForInternet {
    Write-Host "[Check] Dang kiem tra ket noi Internet..." -ForegroundColor Gray
    $retry = 0
    while ($retry -lt 6) { 
        if (Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet) {
            Write-Host "[OK] Da ket noi Internet thanh cong!" -ForegroundColor Green
            return $true
        }
        Write-Host "[!] Chua co Internet. Dang cho ket noi lai (Thu lai sau 5s)..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        $retry++
    }
    Write-Host "[ERROR] Khong co Internet! Cac buoc tai file tu Cloud se bi bo qua." -ForegroundColor Red
    return $false
}

$HasInternet = Wait-ForInternet

# ------------------------------------------------------------------------------
# 0. KHI TAO WINGET CO SAN TREN WINDOWS 11
# ------------------------------------------------------------------------------

# Write-Host "`n[0/7] Dang kich hoat tinh nang WinGet mac dinh cua Windows..." -ForegroundColor Yellow
#
# $WingetBin = "winget"
# $WingetPack = Get-ChildItem -Path "C:\Program Files\WindowsApps\" -Filter "Microsoft.DesktopAppInstaller*_x64__8wekyb3d8bbwe" |
#               Sort-Object LastWriteTime -Descending | Select-Object -First 1
# if ($WingetPack) {
#     $WingetBin = "$($WingetPack.FullName)\winget.exe"
#     $Env:Path += ";$($WingetPack.FullName)"
# }
#
# if ($HasInternet) {
#     try {
#         Start-Process -FilePath $WingetBin -ArgumentList "source list" -NoNewWindow -Wait -ErrorAction SilentlyContinue
#         Write-Host "[OK] WinGet da san sang lam viec!" -ForegroundColor Green
#     }
#     catch {
#         Write-Host "[WARNING] Khong the khoi tao nguon WinGet, se thu chay truc tiep." -ForegroundColor Yellow
#     }
# }

# ------------------------------------------------------------------------------
# 1. CAI DAT UNG DUNG QUA WINGET 
# ------------------------------------------------------------------------------
# Write-Host "`n[1/7] Tien hanh cai dat danh sach ung dung chuan Enterprise..." -ForegroundColor Yellow
#
# if ($HasInternet) {
#     try {
#         Start-Process -FilePath $WingetBin -ArgumentList "source reset --force" -NoNewWindow -Wait -ErrorAction SilentlyContinue
#
#         $AppList = @(
#             "ONLYOFFICE.DesktopEditors",
#             "VideoLAN.VLC",
#             "JAMSoftware.Treesize.Free",
#             "ShareX.ShareX",
#             "7zip.7zip",
#             "XnSoft.XnView.Classic",
#             "Foxit.FoxitReader"
#         )
#
#         $WingetArgs = "--scope machine --silent --accept-package-agreements --accept-source-agreements"
#
#         foreach ($App in $AppList) {
#             Write-Host "-> Dang trien khai cai dat: $App..." -ForegroundColor Gray
#             $Process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$WingetBin`" install --id $App $WingetArgs" -NoNewWindow -PassThru
#
#             $TimeoutCounter = 0
#             while (-not $Process.HasExited -and $TimeoutCounter -lt $GlobalTimeoutSec) {
#                 Start-Sleep -Seconds 2
#                 $TimeoutCounter += 2
#             }
#             if (-not $Process.HasExited) {
#                 Write-Host "[TIMEOUT] Ung dung $App qua thoi gian, tien hanh ngat de chuyen app tiep theo." -ForegroundColor Red
#                 Stop-Process -Id $Process.Id -Force
#             }
#             Write-Host "[VERIFY] Hoan tat tien trinh goi $App." -ForegroundColor DarkGray
#         }
#     }
#     catch {
#         Write-Host "[ERROR] Co loi xay ra trong qua trinh cai app winget: $_" -ForegroundColor Red
#     }
# }

# Loai bo shortcut ngoai man hinh Public
# $PublicDesktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
# $ShortcutsToDelete = @("ONLYOFFICE*", "VLC*", "TreeSize*", "ShareX*", "7-Zip*", "XnView*", "Foxit*")
# foreach ($Pattern in $ShortcutsToDelete) {
#     Get-ChildItem -Path $PublicDesktop -Filter $Pattern -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse
# }

# ------------------------------------------------------------------------------
# 2. TAI VA THIET LAP BO GO UNIKEY
# ------------------------------------------------------------------------------
# Write-Host "`n[2/7] Dang tai va cau hinh bo go UniKey..." -ForegroundColor Yellow
#
# try {
#     $UnikeyUrl = "https://www.unikey.org/assets/release/unikey46RC2-230919-win64.zip"
#     $UnikeyDir = "C:\UniKey"
#     $ZipPath = "$env:TEMP\unikey.zip"
#
#     if (-not (Test-Path $UnikeyDir)) { New-Item -ItemType Directory -Path $UnikeyDir -Force | Out-Null }
#
#     if ($HasInternet) {
#         Write-Host "-> Dang tai UniKey tu trang chu..." -ForegroundColor Gray
#         Invoke-WebRequest -Uri $UnikeyUrl -OutFile $ZipPath -UseBasicParsing -TimeoutSec $GlobalTimeoutSec
#
#         Write-Host "-> Tien hanh xa nen file zip..." -ForegroundColor Gray
#         Expand-Archive -Path $ZipPath -DestinationPath $UnikeyDir -Force
#         Remove-Item -Path $ZipPath -Force
#
#         if (Test-Path "$UnikeyDir\UniKeyNT.exe") {
#             Write-Host "[VERIFY SUCCESS] Bo go UniKey da san sang tai $UnikeyDir" -ForegroundColor Green
#         }
#     }
# }
# catch {
#     Write-Host "[ERROR] Loi xu ly UniKey: $_" -ForegroundColor Red
# }

# ------------------------------------------------------------------------------
# 3. TAO FILE GHI CHU (NOTES.TXT) TU CORESYSTEM
# ------------------------------------------------------------------------------
Write-Host "`n[3/7] Dang dong bo file Notes.txt tu CoreSystem ra Desktop..." -ForegroundColor Yellow

try {
    $CurrentDesktop = [Environment]::GetFolderPath("Desktop")
    $NotePath = "$CurrentDesktop\Notes.txt"
    $NotesUrl = "https://coresystem.vn/osd/Notes-Tweaks.txt"

    if ($HasInternet) {
        Invoke-WebRequest -Uri $NotesUrl -OutFile $NotePath -UseBasicParsing -TimeoutSec 60
        if (Test-Path $NotePath) {
            Write-Host "[VERIFY SUCCESS] Dong bo file Notes.txt thanh cong!" -ForegroundColor Green
        }
    }
}
catch {
    Write-Host "[ERROR] Khong the tai file Notes.txt tu CoreSystem: $_" -ForegroundColor Red
}

# ------------------------------------------------------------------------------
# 4. SET WALLPAPER DESKTOP TU LINK CORESYSTEM
# ------------------------------------------------------------------------------
Write-Host "`n[4/7] Dang tai va ap dung anh nen Desktop tu CoreSystem..." -ForegroundColor Yellow

try {
    $WallpaperUrl = "https://coresystem.vn/osd/wallpaper.jpg"
    $LocalWallpaperFolder = "C:\Windows\Web\Wallpaper\CoreSystem"
    $LocalWallpaperPath = "$LocalWallpaperFolder\wallpaper.jpg"

    if (-not (Test-Path $LocalWallpaperFolder)) { New-Item -ItemType Directory -Path $LocalWallpaperFolder -Force | Out-Null }

    if ($HasInternet) {
        Invoke-WebRequest -Uri $WallpaperUrl -OutFile $LocalWallpaperPath -UseBasicParsing -TimeoutSec $GlobalTimeoutSec
        
        if (Test-Path $LocalWallpaperPath) {
            $Code = @'
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
'@
            Add-Type -TypeDefinition $Code -ErrorAction SilentlyContinue
            [Wallpaper]::SystemParametersInfo(0x0014, 0, $LocalWallpaperPath, 0x01 -bor 0x02) | Out-Null
            
            $RegistryPath = "HKCU:\Control Panel\Desktop"
            Set-ItemProperty -Path $RegistryPath -Name Wallpaper -Value $LocalWallpaperPath -Force
            Write-Host "[VERIFY SUCCESS] Da thiet lap anh nen CoreSystem thanh cong!" -ForegroundColor Green
        }
    }
}
catch {
    Write-Host "[ERROR] Khong ap dung duoc hinh nen: $_" -ForegroundColor Red
}

# ------------------------------------------------------------------------------
# 5. TINH CHINH UNG DUNG (MICROSOFT EDGE & FOXIT PDF)
# ------------------------------------------------------------------------------
# Write-Host "`n[5/7] Dang tien hanh ap dung Tweak cau hinh cho ung dung..." -ForegroundColor Yellow
#
# # --- a. Microsoft Edge Tweaks (Ghi vao Default User RunOnce de tu dong chay khi User dang nhap) ---
# try {
#     Write-Host "-> Dang nap kich ban setup Edge vao Default User RunOnce..." -ForegroundColor Gray
#
#     # Nap nhanh Registry cua Default User de tac dong den moi User tao sau nay
#     Reg load HKU\DefaultUser C:\Users\Default\NTUSER.DAT | Out-Null
#
#     # 1. Khai bao cac thiet lap Edge cho may doanh nghiep (HKLM cap thiet bi)
#     $EdgeHKLM = "Registry::HKLM\SOFTWARE\Policies\Microsoft\Edge"
#     if (-not (Test-Path $EdgeHKLM)) { New-Item -Path $EdgeHKLM -Force | Out-Null }
#     Set-ItemProperty -Path $EdgeHKLM -Name "HideFirstRunExperience" -Value 1 -Type DWord -Force
#     Set-ItemProperty -Path $EdgeHKLM -Name "ShowHomeButton" -Value 1 -Type DWord -Force
#
#     # Force extension uBlock (Muc nay Edge van cho phep chay qua HKLM tren may Workgroup)
#     $EdgeExt = "Registry::HKLM\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist"
#     if (-not (Test-Path $EdgeExt)) { New-Item -Path $EdgeExt -Force | Out-Null }
#     Set-ItemProperty -Path $EdgeExt -Name "1" -Value "pciakllldcajllepkbbihkmfkikheffb;https://edge.microsoft.com/extensionwebstorebase/v1/crx" -Force
#
#     # 2. Tao file Script nho bat cuong che Homepage dat tai o C
#     $EdgeUserScript = @"
# `$EdgeHKCU = \"HKCU:\Software\Microsoft\Edge\PreferenceMacroDefs\"
# if (-not (Test-Path `$EdgeHKCU)) { New-Item -Path `$EdgeHKCU -Force | Out-Null }
# Set-ItemProperty -Path \"HKCU:\Software\Microsoft\Edge\Main\" -Name \"HomeButtonPage\" -Value \"https://www.google.com\" -Force
# Set-ItemProperty -Path \"HKCU:\Software\Microsoft\Edge\Main\" -Name \"SyncHomepageWithNewTabPage\" -Value 0 -Type DWord -Force
# "@
#     $ScriptDir = "C:\CoreSystem"
#     if (-not (Test-Path $ScriptDir)) { New-Item -ItemType Directory -Path $ScriptDir -Force | Out-Null }
#     Out-File -FilePath "$ScriptDir\EdgeUserTweak.ps1" -InputObject $EdgeUserScript -Encoding utf8 -Force
<#
    # 3. Dang ky vao RunOnce cua Default User de khi User log vao la tu kich hoat am tham
    $DefaultRunOnce = "Registry::HKU\DefaultUser\Software\Windows\CurrentVersion\RunOnce"
    if (-not (Test-Path $DefaultRunOnce)) { New-Item -Path $DefaultRunOnce -Force | Out-Null }
    Set-ItemProperty -Path $DefaultRunOnce -Name "EdgeHomepageFix" -Value "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\CoreSystem\EdgeUserTweak.ps1" -Force

    # Giai phong nhanh Default User sau khi nap xong
    Reg unload HKU\DefaultUser | Out-Null
    Write-Host "[VERIFY SUCCESS] Da thiet lap luong RunOnce cho Edge!" -ForegroundColor Green
}
catch {
    Write-Host "[WARNING] Gap loi khi cau hinh Edge: $_" -ForegroundColor Yellow
    # Dam bao luon unload keo ket luong Registry he thong
    Reg unload HKU\DefaultUser -ErrorAction SilentlyContinue | Out-Null
}

# --- b. Foxit PDF Reader Tweaks ---
try {
    Write-Host "-> Dang cau hinh Foxit PDF Reader..." -ForegroundColor Gray
    Reg load HKU\DefaultUser C:\Users\Default\NTUSER.DAT | Out-Null

    $FoxitRegistryPaths = @(
        "Registry::HKU\DefaultUser\Software\Foxit Software\Foxit PDF Reader 1.0\Preferences\General",
        "Registry::HKU\DefaultUser\Software\Foxit Software\Foxit PDF Reader 2026\Preferences\General"
    )

    foreach ($Path in $FoxitRegistryPaths) {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        Set-ItemProperty -Path $Path -Name "bShowStartPage" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $Path -Name "bShowAdvertisement" -Value 0 -Type DWord -ErrorAction SilentlyContinue
    }

    Reg unload HKU\DefaultUser | Out-Null
    Write-Host "[VERIFY SUCCESS] Tweak cau hinh Foxit Reader thanh cong!" -ForegroundColor Green
}
catch {
    Write-Host "[WARNING] Gap loi khi cau hinh Foxit Reader, tu dong bo qua: $_" -ForegroundColor Yellow
    Reg unload HKU\DefaultUser -ErrorAction SilentlyContinue | Out-Null
}#>

# ------------------------------------------------------------------------------
# 6. DON DEP HE THONG
# ------------------------------------------------------------------------------
Write-Host "`n[6/7] Dang thuc hien quy trinh don dep he thong..." -ForegroundColor Yellow

try {
    Write-Host "-> Dang quet sach toan bo Event Logs..." -ForegroundColor Gray
    Get-EventLog -LogName * -ErrorAction SilentlyContinue | ForEach-Object { Clear-EventLog -LogName $_.Log -ErrorAction SilentlyContinue }

    Write-Host "-> Dang ky tien trinh tu huy Panther va CoreSystem sau khi restart..." -ForegroundColor Gray
    $RunOncePath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
    Set-ItemProperty -Path $RunOncePath -Name "CleanupPanther" -Value "cmd.exe /c rmdir /s /q C:\Windows\System32\Panther" -Force
    Set-ItemProperty -Path $RunOncePath -Name "CleanupCoreSystem" -Value "cmd.exe /c rmdir /s /q C:\CoreSystem" -Force

    Write-Host "[VERIFY SUCCESS] Da dat lich don dep he thong khi khoi dong lai may!" -ForegroundColor Green
}
catch {
    Write-Host "[WARNING] Loi khi don dep he thong: $_" -ForegroundColor Yellow
}

# ------------------------------------------------------------------------------
# 7. KHOI PHUC TRANG THAI BAO MAT POWERSHELL (EXECUTIONPOLICY)
# ------------------------------------------------------------------------------
Write-Host "`n[7/7] Dang khoi phuc lai ExecutionPolicy nguyen ban..." -ForegroundColor Yellow

try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
    if ((Get-ExecutionPolicy -Scope LocalMachine) -eq "RemoteSigned") {
        Write-Host "[VERIFY SUCCESS] Trang thai bao mat PowerShell da ve: RemoteSigned" -ForegroundColor Green
    }
}
catch {
    Write-Host "[WARNING] Khong the thiet lap lai ExecutionPolicy: $_" -ForegroundColor Yellow
}

# Thiet lap high performance

try {
    $guid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
    powercfg /q $guid *>$null
    if ($?) { powercfg /setactive $guid }
} catch { }

Write-Host "`n=== [HOAN TAT] HE THONG SAN SANG KHOI DONG LAI CHINH THUC ===" -ForegroundColor Green

Restart-Computer
