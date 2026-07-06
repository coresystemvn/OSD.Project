# ==============================================================================
# SCRIPT INJECT CONFIG - NHANH PXE (X:\Windows\System32\next-step.ps1)
# By Tran Trung Truc (tructransecure@gmail.com)
# ==============================================================================

Write-Host "[Monitor] OSDCloud da hoan tat. Bat dau quet kho cau hinh PXE..." -ForegroundColor Green

# 1. Dinh vi thu muc SetupFiles co dinh tren Ramdisk X của ban build PXE
$SourcePath = "X:\SetupFiles"

if (-not (Test-Path $SourcePath)) {
    Write-Host "[ERROR] Khong tim thay thu muc SetupFiles tren o X! Vui long kiem tra lai boot.wim" -ForegroundColor Red
    Start-Sleep -Seconds 5
    Exit
}

# 2. Dinh vi phan vung Windows tren o cung vua bung Image
$TargetDrive = (Get-Volume | Where-Object { Test-Path "$($_.DriveLetter):\Windows\System32" } | Select-Object -First 1).DriveLetter
if (-not $TargetDrive) {
    Write-Host "[ERROR] Khong tim thay o cai Windows tren dia cung!" -ForegroundColor Red
    Start-Sleep -Seconds 5
    Exit
}
$TargetOS = "$($TargetDrive):"

# 3. Copy file cau hinh vao o cung muc tieu
try {
    $PantherPath = "$TargetOS\Windows\Panther"
    $CoreSystemPath = "$TargetOS\CoreSystem"
    if (-not (Test-Path $PantherPath)) { New-Item -ItemType Directory -Path $PantherPath -Force | Out-Null }
    if (-not (Test-Path $CoreSystemPath)) { New-Item -ItemType Directory -Path $CoreSystemPath -Force | Out-Null }

    if (Test-Path "$SourcePath\unattend.xml") { 
        Copy-Item -Path "$SourcePath\unattend.xml" -Destination "$PantherPath\unattend.xml" -Force 
        Write-Host "[SUCCESS] Da inject file Unattend.xml" -ForegroundColor Green
    }
    if (Test-Path "$SourcePath\post-setup-tweaks.ps1") {
        Copy-Item -Path "$SourcePath\post-setup-tweaks.ps1" -Destination "$CoreSystemPath\Post-setup.ps1" -Force
        Write-Host "[SUCCESS] Da inject file Post-setup.ps1" -ForegroundColor Green
    }
    
    Write-Host "[SUCCESS] Da hoan tat quy trinh tinh chinh PXE! Restart sau 5 giay..." -ForegroundColor Green
    Start-Sleep -Seconds 5
    wpeutil reboot
}
catch {
    Write-Host "[ERROR] Loi copy du lieu: $_" -ForegroundColor Red
    Start-Sleep -Seconds 10
}
