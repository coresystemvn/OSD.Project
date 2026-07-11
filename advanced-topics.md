# Advanced Topics
> Dành cho: IT Pro muốn tùy biến sâu và tự chủ nền tảng

---

# Chủ đề nâng cao
> For: IT Pros who want deep customization and full platform control

---

## Mục lục

1. [Hiểu hệ thống](#hiểu-hệ-thống)
2. [Kiến trúc hiện tại](#kiến-trúc-hiện-tại)
3. [Tùy biến Wallpaper](#tùy-biến-wallpaper)
4. [Tùy biến SetupFiles](#tùy-biến-setupfiles)
5. [Portable Apps](#portable-apps)
6. [Testing](#testing)
7. [PXE Environment](#pxe-environment)
8. [Troubleshooting](#troubleshooting)

---

## Hiểu hệ thống

### OSDeploy vs OSDCloud

| Module | Chú ý | Ổn định |
|--------|-------|---------|
| **OSDeploy** | Build boot, driver, ISO | ✅ Ổn định |
| **OSDCloud** | Tải & cài Windows từ Microsoft | ⚠️ Thay đổi theo phiên bản |

**Lưu ý:** OSDCloud internals thay đổi theo phiên bản. OSD Project hoạt động như một **lớp vỏ (shell layer)**, không can thiệp luồng chạy hay thiết lập ban đầu của OSDCloud.

---

## Kiến trúc hiện Tại

### Khái niệm "Shell Layer"

OSD Project **không can thiệp** vào luồng chạy hay thiết lập ban đầu của OSDCloud. Hệ thống hoạt động như một lớp vỏ bọc bên ngoài, tương tác với OSDCloud thông qua CLI (Command Line Interface).

**So sánh:**

| Phiên bản | Cách tiếp cận | Ghi chú |
|-----------|---------------|---------|
| **Cũ (wiki)** | Gọi `Deploy-OSDCloudGUI` | Can thiệp giao diện gốc |
| **Mới** | Gọi `Deploy-OSDCloudCLI` | Không can thiệp, chỉ truyền tham số |

### Flow vận hành mới

```
WinPE boot
    ↓
startnet.cmd / winpeshl.ini
    ↓
coresystem-ng.ps1 (Menu chính)
    ↓
User chọn luồng cài: 1 | 2 | 3
    │
    ├── 1. Setup Windows default
    ├── 2. With tweaks
    └── 3. Combo tweaks + apps
    ↓
Dialog OS Configurator hiện lên
    │
    ├── User chọn: OS version | Edition | Language | Activation mode
    └── System gọi Deploy-OSDCloudCLI với tham số đã chọn
    ↓
Deployment window hiện quá trình cài đặt
    ↓
Cuối tiến trình: inject SetupFiles → Reboot
    ↓
unattend.xml chạy tự động
    ↓
Post-setup.ps1 chạy lần đăng nhập đầu tiên
```

### Tại sao dùng CLI thay vì GUI?

- **OSDCloud hỗ trợ CLI** - Phiên bản mới cho phép gọi trực tiếp
- **Không cần tùy biến giao diện gốc** - Giảm phụ thuộc vào thay đổi của tác giả
- **Tùy biến giao diện bằng PowerShell + XAML** - Dễ maintain hơn
- **Ổn định hơn** - Không can thiệp luồng chạy của OSDCloud

### Các bước cụ thể

1. **User bấm chọn luồng cài 1|2|3**
   - Hệ thống hiển thị dialog OS Configurator
   - User chọn OS version, edition, language, activation mode

2. **Gọi Deploy-OSDCloudCLI**
   - Hệ thống truyền các tham số đã chọn
   - OSDCloud chạy nền, không hiện GUI gốc

3. **Hiển thị deployment window**
   - Quá trình cài đặt được thể hiện qua window
   - User theo dõi tiến trình

4. **Kết thúc**
   - Inject SetupFiles (unattend.xml + post-setup.ps1)
   - Reboot → unattend.xml chạy tự động
   - Post-setup.ps1 chạy lần đăng nhập đầu tiên

---

## Tùy biến Wallpaper

### 2 cách thay wallpaper

**Cách 1: Tự động (khuyên dùng)**

Đặt file wallpaper vào thư mục `%ProgramData%\OSDeployCore\OSDRepo\` với tên `winpe-wallpaper`. Khi build, hệ thống sẽ copy tự động vào boot.wim.

**Cách 2: Thủ công**

Sau khi mount boot.wim:
1. Rename wallpaper thành `winpe.jpg`
2. Copy vào `[MountPath:\Windows\System32\]`
3. Unmount /commit

**Lưu ý:**
- Wallpaper đặt ở `X:\Windows\System32\winpe.jpg` khi WinPE chạy
- UEFI SecureBoot không áp dụng config kiểu cũ, nên thiết kế cho độ phân giải an toàn 1024x768
- Đặt logo ở vị trí không bị che bởi menu

---

## Tùy biến SetupFiles

### Cấu trúc

```
X:\SetupFiles\
├── unattend.xml          # Tự động hóa Windows setup
├── post-setup-tweaks.ps1 # Cài app, tweak hệ thống
└── post-setup-combo.ps1  # Combo tweaks + apps
```

### unattend.xml

Tạo từ [Schneegans Unattend Generator](https://schneegans.de/windows/unattend-generator).

File này được `next-step-{}.ps1` inject vào `C:\Windows\Panther\` khi kết thúc quá trình cài đặt.

**Tham số phổ biến:**
- Skip OOBE
- Debloat
- Tạo user mặc định
- Auto login
- Set timezone, language

### Post-setup.ps1

Chạy ở lần đăng nhập đầu tiên. Nhiệm vụ:
- Cài app qua winget
- Tweak hệ thống (tắt telemetry, tối ưu performance)
- Đặt hình nền
- Tải file Notes.txt
- Dọn dẹp & khởi động lại

**Lưu ý:**
- Không tải winget-cli mới từ GitHub (dễ lỗi)
- Tận dụng winget có sẵn trên máy
- Tạo vòng lặp xác thực mỗi bước

---

## Portable Apps

### Vị trí

```
X:\Softwares\
├── HWInfo32/        # Thông tin phần cứng
├── Multidrive/      # Backup ổ đĩa
├── Explorer++/      # Duyệt file
└── (thêm app khác)
```

### Nguyên tắc chọn app

1. **Chạy được trên WinPE** - Không phải app nào cũng chạy được
2. **Hợp pháp** - Free hoặc open source
3. **Nhẹ** - Không chiếm quá nhiều tài nguyên
4. **Cần thiết** - Phù hợp nhu cầu IT

### Gọi app

App được gọi trực tiếp từ `coresystem-ng.ps1`:

```powershell
# Ví dụ gọi HWInfo
Start-Process "X:\Softwares\HWInfo32\HWInfo.exe"
```

---

## Testing

### Build machine vs Test machine

| Giai đoạn | Yêu cầu | Ghi chú |
|-----------|----------|---------|
| **Build ISO** | PowerShell 7.6, máy vật lý | OSDeploy yêu cầu physical machine |
| **Test ISO** | VM hoặc máy vật lý | Sau khi build xong, test ở đâu cũng được |

### Test trên Hyper-V

1. Tạo VM mới (Gen 2)
2. Bật UEFI: VM Settings → Security → Check "Enable Secure Boot"
3. Bật TPM 2.0: VM Settings → Security → Check "Enable Trusted Platform Module"
4. Mount file ISO đã build
5. Boot VM

**Lưu ý:**
- Hyper-V Type 2 mặc định UEFI
- OSD Project **không hỗ trợ legacy BIOS**, chỉ UEFI
- Hệ thống khi public source đã test kỹ trên cả VM và physical machine

### Test trên máy vật lý

1. Tạo USB boot bằng Rufus từ file ISO
2. Boot máy từ USB
3. Kiểm tra các chức năng:
   - Kết nối WiFi
   - Các công cụ (Disk Backup, File Explorer, Hardware Info)
   - Cài đặt Windows

---

## PXE Environment

Boot từ network thay vì USB/DVD.

### Yêu cầu

- Server DHCP/TFTP
- Boot image (boot.wim) share qua network
- Client hỗ trợ PXE boot

### Cấu hình

1. Copy boot.wim lên server share
2. Cấu hình DHCP để hướng dẫn client boot từ network
3. Client boot → Tải boot.wim → Khởi động CoreSystem

---

## Troubleshooting

### Build trên VM lỗi

**Nguyên nhân:** OSDeploy từ chối build trên VM

**Giải pháp:** Thêm `<smbios mode='host'/>` vào file XML. Áp dụng cho QEMU. Với HyperV và VMware, tìm hiểu thêm ở search engine

```xml
</os>
<smbios mode='host'/>
```

---

### Lỗi tiếng Việt có dấu

**Nguyên nhân:** WinPE không hỗ trợ font tiếng Việt đầy đủ

**Giải pháp:** Sử dụng tiếng Việt không dấu trong file PS

---

### Lỗi cài Windows

**Nguyên nhân:** Không có kết nối Internet

**Giải pháp:** Kiểm tra cable mạng hoặc WiFi

---

### Firewall block

**Nguyên nhân:** Corporate firewall chặn Microsoft Store, GitHub

**Giải pháp:** Bỏ chặn các nhóm địa chỉ:
- Microsoft Store
- GitHub
- Winget source

---

### Unmount /commit lỗi

**Nguyên nhân:** Có cửa sổ đang truy cập thư mục mount

**Giải pháp:**
1. Đóng tất cả cửa sổ liên quan
2. `Dism /Unmount-Wim /MountDir:"C:\Boot" /Discard`
3. Thực hiện lại

---

### Dialog OS Configurator không hiện

**Nguyên nhân:** File coresystem-ng.exe hoặc coresystem-ng.ps1 bị lỗi đường dẫn

**Giải pháp:** Kiểm tra lại file structure trong X:\Windows\System32

---

### Deploy-OSDCloudCLI không chạy

**Nguyên nhân:** OSDCloud version không hỗ trợ CLI

**Giải pháp:** Cập nhật OSDCloud module lên phiên bản mới nhất

---

## Notes

### Quá trình phát triển

- **Phiên bản cũ:** Gọi `Deploy-OSDCloudGUI`, can thiệp giao diện gốc
- **Phiên bản mới:** Gọi `Deploy-OSDCloudCLI`, hoạt động như shell layer
- **UI/UX:** Xây dựng bằng PowerShell + XAML dialogs

### Dọn dẹp build machine

Sau khi hoàn thành build & test:
- Xóa `%ProgramData%\OSDeployCore` nếu không dùng
- Giữ lại file ISO đã build thành công

---

## Cần giúp đỡ?

- **GitHub Issues:** Báo lỗi và đề xuất
- **Cộng đồng:** Hỗ trợ lẫn nhau

---
---

# Advanced Topics
> For: IT Pros who want deep customization and full platform control

---

## Table of Contents

1. [Understand the system](#understand-the-system)
2. [Current architecture](#current-architecture)
3. [Customize SetupFiles](#customize-setupfiles)
4. [Portable Apps](#portable-apps-1)
5. [PXE Environment](#pxe-environment-1)
6. [Troubleshooting](#troubleshooting-1)

---

## Understand the system

### OSDeploy vs OSDCloud

| Module | Purpose | Stability |
|--------|---------|-----------|
| **OSDeploy** | Build boot, drivers, ISO | ✅ Stable |
| **OSDCloud** | Download & install Windows from Microsoft | ⚠️ Changes per version |

**Note:** OSDCloud internals change with each version. OSD Project operates as a **shell layer**, not intervening in OSDCloud's flow or initial settings.

---

## Current Architecture

### Shell Layer Concept

OSD Project **does not intervene** in OSDCloud's flow or initial settings. The system operates as an outer shell, interacting with OSDCloud via CLI (Command Line Interface).

**Comparison:**

| Version | Approach | Note |
|---------|----------|------|
| **Old (wiki)** | Called `Deploy-OSDCloudGUI` | Intervened in author's GUI |
| **New** | Calls `Deploy-OSDCloudCLI` | No intervention, only passes parameters |

### New operation flow

```
WinPE boot
    ↓
startnet.cmd / winpeshl.ini
    ↓
coresystem-ng.ps1 (Main menu)
    ↓
User selects install flow: 1 | 2 | 3
    │
    ├── 1. Setup Windows default
    ├── 2. With tweaks
    └── 3. Combo tweaks + apps
    ↓
OS Configurator dialog appears
    │
    ├── User selects: OS version | Edition | Language | Activation mode
    └── System calls Deploy-OSDCloudCLI with selected parameters
    ↓
Deployment window shows installation progress
    ↓
End of process: inject SetupFiles → Reboot
    ↓
unattend.xml runs automatically
    ↓
Post-setup.ps1 runs on first login
```

### Why use CLI instead of GUI?

- **OSDCloud supports CLI** - Newer versions allow direct CLI calls
- **No need to modify author's GUI** - Reduces dependency on author's changes
- **Build UI with PowerShell + XAML** - Easier to maintain
- **More stable** - Does not intervene in OSDCloud's flow

### Specific steps

1. **User selects install flow 1|2|3**
   - System shows OS Configurator dialog
   - User selects OS version, edition, language, activation mode

2. **Call Deploy-OSDCloudCLI**
   - System passes selected parameters
   - OSDCloud runs in background, no original GUI shown

3. **Show deployment window**
   - Installation process displayed via window
   - User monitors progress

4. **Completion**
   - Inject SetupFiles (unattend.xml + post-setup.ps1)
   - Reboot → unattend.xml runs automatically
   - Post-setup.ps1 runs on first login

---

## Customize SetupFiles

### Structure

```
X:\SetupFiles\
├── unattend.xml          # Automate Windows setup
├── post-setup-tweaks.ps1 # Install apps, system tweaks
└── post-setup-combo.ps1  # Combo tweaks + apps
```

### unattend.xml

Created from [Schneegans Unattend Generator](https://schneegans.de/windows/unattend-generator).

This file is injected by `next-step-{}.ps1` into `C:\Windows\Panther\` when installation completes.

**Common parameters:**
- Skip OOBE
- Debloat
- Create default user
- Auto login
- Set timezone, language

### Post-setup.ps1

Runs on first login. Responsibilities:
- Install apps via winget
- System tweaks (disable telemetry, optimize performance)
- Set wallpaper
- Download Notes.txt
- Cleanup & restart

**Note:**
- Do not download new winget-cli from GitHub (prone to errors)
- Use existing winget on machine
- Create validation loop for each step

---

## Portable Apps

### Location

```
X:\Softwares\
├── HWInfo32/        # Hardware information
├── Multidrive/      # Disk backup
├── Explorer++/      # File browser
└── (other apps)
```

### App selection principles

1. **Runs on WinPE** - Not all apps work in PE environment
2. **Legal** - Free or open source
3. **Lightweight** - Does not consume too many resources
4. **Necessary** - Fits IT needs

### Calling apps

Apps are called directly from `coresystem-ng.ps1`:

```powershell
# Example: Call HWInfo
Start-Process "X:\Softwares\HWInfo32\HWInfo.exe"
```

---

## PXE Environment

Boot from network instead of USB/DVD.

### Requirements

- DHCP/TFTP server
- Boot image (boot.wim) shared via network
- Client supports PXE boot

### Configuration

1. Copy boot.wim to server share
2. Configure DHCP to direct client to boot from network
3. Client boot → Downloads boot.wim → Starts CoreSystem

---

## Troubleshooting

### Build on VM fails

**Cause:** OSDeploy rejects VM builds

**Solution:** Add `<smbios mode='host'/>` to XML file for QEMU. In case of HyperV or VMware Workstation, refer search engine for more details

```xml
</os>
<smbios mode='host'/>
```

---

### Vietnamese diacritics error

**Cause:** WinPE doesn't fully support Vietnamese fonts

**Solution:** Use Vietnamese without diacritics in PS files

---

### Windows install error

**Cause:** No Internet connection

**Solution:** Check network cable or WiFi

---

### Firewall block

**Cause:** Corporate firewall blocks Microsoft Store, GitHub

**Solution:** Unblock these address groups:
- Microsoft Store
- GitHub
- Winget source

---

### Unmount /commit error

**Cause:** Window accessing mount directory

**Solution:**
1. Close all related windows
2. `Dism /Unmount-Wim /MountDir:"C:\Boot" /Discard`
3. Redo

---

### OS Configurator dialog doesn't appear

**Cause:** coresystem-ng.exe or coresystem-ng.ps1 has path error

**Solution:** Check file structure in X:\Windows\System32

---

### Deploy-OSDCloudCLI doesn't run

**Cause:** OSDCloud version doesn't support CLI

**Solution:** Update OSDCloud module to latest version

---

## Notes

### Development process

- **Old version:** Called `Deploy-OSDCloudGUI`, intervened in author's GUI
- **New version:** Calls `Deploy-OSDCloudCLI`, operates as shell layer
- **UI/UX:** Built with PowerShell + XAML dialogs

### Build machine cleanup

After completing build & test:
- Delete `%ProgramData%\OSDeployCore` if not needed
- Keep successfully built ISO file

---

## Need Help?

- **GitHub Issues:** Report bugs and suggestions
- **Community:** Peer support
