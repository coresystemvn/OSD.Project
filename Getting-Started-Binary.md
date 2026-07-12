# Getting Started (Phiên bản Binary)
> Dành cho: Kỹ thuật viên IT muốn triển khai nhanh

---

**Ghi chú:** Đây là lối tắt cho ai muốn nhanh nhất có đĩa boot. Dự án không chia sẻ file .iso pre-built để tránh vi phạm bản quyền. Làm theo từng bước là được.

**Thông tin kỹ thuật:** Phiên bản này được refactor hoàn toàn sang C# WPF (.NET 10) để tối ưu hóa tốc độ thực thi trong môi trường WinPE, mang lại UX mượt mà hơn trong khi vẫn giữ nguyên bộ tính năng cốt lõi của dự án.

---

## Yêu cầu hệ thống

- Windows 11 (24H2 hoặc 25H2)
- PowerShell 7.6 trở lên
- USB drive (8GB trở lên)
- File ISO Windows 11

**Quan trọng:** 
- Luôn chạy terminal/PowerShell ở chế độ Administrator.
- **Yêu cầu bắt buộc:** Do kiến trúc các module OSDeploy đòi hỏi truy cập trực tiếp vào phần cứng để build boot, bạn **bắt buộc phải build trên máy vật lý**. Sau khi build xong ISO, bạn có thể kiểm thử (test) trên máy ảo hoặc máy vật lý tùy ý.
- **Tính ổn định:** Để tránh ảnh hưởng từ các thay đổi của OSDCloud upstream, hãy sử dụng các module PowerShell đã được cung cấp trong thư mục `Misc/` của dự án.

---

## Bước 1: Tải Binary

Tải file binary self-contained (~128MB) từ link bên dưới:

[Tải về](https://github.com/coresystemvn/OSD.Project/releases)

---

## Bước 2: Tạo WinPE (5 lệnh)

Mở PowerShell với quyền Administrator và chạy lần lượt:

```powershell
# 1. Cài module OSDeploy và OSDCloud
Install-Module -Name OSDeploy -Force -SkipPublisherCheck
Install-Module -Name OSDCloud -Force -SkipPublisherCheck

# 2. Cài các thành phần phụ thuộc
Install-OSDeploySoftware -Force

# 3. Cập nhật driver lần 1 (từ Internet: Dell/HP/Microsoft...)
Update-OSDeployCoreDrivers

# 4. Import file ISO Windows 11
Import-OSDeployCoreOS

# 5. Cập nhật driver lần 2 (WinRE tích hợp driver WiFi)
Update-OSDeployCoreDrivers

# 6. Build file boot
Build-OSDeployBoot -Name 'CoreSystem'

# 7. Tạo file ISO
Update-OSDeployBootISO
```

**Lưu ý:** File ISO hoàn chỉnh khoảng ~1.3GB

---

## Bước 3: Tùy chỉnh WinPE

### 3.1 Tạo thư mục mount và Mount file boot.wim

Đường dẫn file `boot.wim` phụ thuộc vào máy tính của bạn. Kiểm tra thư mục `C:\ProgramData\OSDeployCore\` để tìm đường dẫn chính xác.

Ví dụ:

```powershell
# Tạo thư mục mount trước
mkdir C:\Boot

# Mount image (ví dụ - đường dẫn máy bạn có thể khác)
dism /mount-image /ImageFile:"C:\ProgramData\OSDeployCore\boot\26100.8455-amd-OSD\bootmedia\sources\boot.wim" /Index:1 /MountDir:"C:\Boot"
```

### 3.2 Copy file theo cấu trúc thư mục

Sau khi mount boot.wim, copy các file theo cấu trúc sau:

```
X:\Windows\System32\
├── coresystem-ng.exe              ← File chính
├── winpeshl.ini                   ← Launcher
├── next-step-tweaks.ps1           ← Inject tweaks vào OS mới
└── next-step-combo.ps1            ← Inject combo vào OS mới

X:\Softwares\                      ← 4 thư mục portableApps
├── (thư mục 1)
├── (thư mục 2)
├── (thư mục 3)
└── (thư mục 4)

X:\SetupFiles\                     ← 3 file post-setup
├── unattend.xml
├── post-setup-tweaks.ps1
└── post-setup-combo.ps1
```

**Giải thích:**
- **Portable apps** được gọi trực tiếp từ `X:\Softwares` khi WinPE hoạt động
- **Khi chạy task cài OS:** Cuối tiến trình sẽ gọi `next-step-{}.ps1`
- **next-step.ps1** sẽ inject files từ `X:\SetupFiles` vào OS mới

### 3.3 Chỉnh sửa winpeshl.ini

File `winpeshl.ini` quyết định chương trình nào chạy khi WinPE khởi động.

Quy trình: WinPE khởi động → `Winpeshl.exe` đọc `winpeshl.ini` → Gọi các ứng dụng theo thứ tự.

**Lưu ý:** File `coresystem-ng.exe` phải nằm trong `X:\Windows\System32`

```ini
[LaunchApps]
%windir%\system32\wpeutil.exe,InitializeNetwork
%windir%\system32\coresystem-ng.exe
```

### 3.4 Unmount /commit

```powershell
# Đóng tất cả cửa sổ truy cập thư mục mount trước khi thực hiện
Dism /Unmount-Wim /MountDir:"C:\Boot" /Commit
```

---

## Checklist

### Yêu cầu hệ thống
- [ ] Windows 11 (24H2/25H2)
- [ ] PowerShell 7.6 đã cài
- [ ] USB drive (8GB+) sẵn sàng
- [ ] File ISO Windows 11 đã tải

### Tạo WinPE
- [ ] Module OSDeploy đã cài
- [ ] Module OSDCloud đã cài
- [ ] Các thành phần phụ thuộc đã cài
- [ ] Driver đã cập nhật lần 1
- [ ] File ISO Windows 11 đã import
- [ ] Driver đã cập nhật lần 2 (WiFi)
- [ ] WinPE đã build thành công
- [ ] File ISO đã tạo (~1.3GB)

### Tùy chỉnh
- [ ] Thư mục mount đã tạo
- [ ] File boot.wim đã mount
- [ ] File đã copy đúng cấu trúc
- [ ] winpeshl.ini đã cấu hình
- [ ] Unmount /commit thành công

### Kiểm tra thành công (Validation)
- [ ] **Kích thước ISO:** Đảm bảo file ISO sau khi build có kích thước khoảng ~1.3GB (± 50MB). Nếu nhỏ hơn đáng kể, quá trình build có thể bị lỗi.
- [ ] **Boot thử:** Hãy boot thử vào máy ảo (Gen 2, hỗ trợ Secure Boot) trước khi mang ra máy vật lý để đảm bảo môi trường WinPE đã khởi động đúng.

---

## Các chủ đề nâng cao
- **[Advanced Topics](./advanced-topics.md)** - Hiểu sâu về kiến trúc hệ thống và tùy biến nâng cao.

## Hỏi đáp

### Tại sao phải cập nhật driver 2 lần?

**Lần 1:** OSDeploy tải driver từ Internet (Dell/HP/Microsoft...)

**Lần 2:** Sau khi import ISO, WinRE đã tích hợp sẵn driver WiFi

**Mục đích:** Đảm bảo WinPE có đủ driver cho đa số thiết bị

---

### Có thể dùng máy ảo để build không?

**Không,** việc build trên máy ảo sẽ bị từ chối.

**Giải pháp:** Sử dụng máy vật lý hoặc áp dụng tweaks để bypass.

---

### Unmount /commit báo lỗi thì làm sao?

**Nguyên nhân:** Có cửa sổ hoặc ứng dụng đang truy cập thư mục mount.

**Giải pháp:** Đóng tất cả cửa sổ liên quan, sau đó Unmount /discard và thực hiện lại.

---

### Ứng dụng không chạy đúng thì kiểm tra gì?

Kiểm tra các mục sau:

1. **Cấu trúc thư mục** - Đã copy đúng vị trí chưa?
2. **winpeshl.ini** - Đã cấu hình đúng chưa?
3. **File coresystem.exe** - Có trong System32 không?

---

### File ISO nặng bao nhiêu?

- **Phiên bản PowerShell:** ~1.1GB
- **Phiên bản Binary:** ~1.3GB

---

### Phải build mấy lần mới được?

Người mới thường cần **2-3 lần thử** mới có kết quả sử dụng được.

Đây là quá trình bình thường, đừng nản lòng!

---

### Có thể tùy chỉnh phiên bản Binary không?

**Giới hạn.** Phiên bản Binary đã được đóng gói self-contained.

Nếu muốn tùy chỉnh sâu, hãy dùng **Phiên bản PowerShell**.

---

### Cần hỗ trợ thì làm sao?

- **GitHub Issues:** Báo lỗi và đề xuất
- **Wiki:** Tài liệu chuyên sâu
- **Cộng đồng:** Hỗ trợ lẫn nhau

**Lưu ý:** Dự án theo định hướng mã nguồn mở, hạn chế support trực tiếp.


---
---
---

# Getting Started (Binary Version)
> For: IT technicians who want quick deployment

---

## Prerequisites

- Windows 11 (24H2 or 25H2)
- PowerShell 7.6 or later
- USB drive (8GB or more)
- Windows 11 ISO file

---

## Step 1: Download Binary

Download the self-contained binary file (~128MB) from the link below:

[Download](https://github.com/coresystemvn/OSD.Project/releases)

---

## Step 2: Create WinPE (5 commands)

Open PowerShell as Administrator and run sequentially:

```powershell
# 1. Install OSDeploy and OSDCloud modules
Install-Module -Name OSDeploy -Force -SkipPublisherCheck
Install-Module -Name OSDCloud -Force -SkipPublisherCheck

# 2. Install prerequisites
Install-OSDeploySoftware -Force

# 3. Update drivers 1st time (from Internet: Dell/HP/Microsoft...)
Update-OSDeployCoreDrivers

# 4. Import Windows 11 ISO file
Import-OSDeployCoreOS

# 5. Update drivers 2nd time (WinRE has WiFi drivers integrated)
Update-OSDeployCoreDrivers

# 6. Build boot file
Build-OSDeployBoot -Name 'CoreSystem'

# 7. Generate ISO file
Update-OSDeployBootISO
```

**Note:** Final ISO file is approximately ~1.3GB

---

## Step 3: Customize WinPE

### 3.1 Create mount directory and Mount boot.wim

The `boot.wim` path depends on your machine. Check the `C:\ProgramData\OSDeployCore\` directory for the correct path.

Example:

```powershell
# Create mount directory first
mkdir C:\Boot

# Mount image (example - your path may differ)
dism /mount-image /ImageFile:"C:\ProgramData\OSDeployCore\boot\26100.8455-amd-OSD\bootmedia\sources\boot.wim" /Index:1 /MountDir:"C:\Boot"
```

### 3.2 Copy files according to directory structure

After mounting boot.wim, copy files according to the following structure:

```
X:\Windows\System32\
├── coresystem-ng.exe              ← Main file
├── winpeshl.ini                   ← Launcher
├── next-step-tweaks.ps1           ← Inject tweaks into new OS
└── next-step-combo.ps1            ← Inject combo into new OS

X:\Softwares\                      ← 4 portableApps folders
├── (folder 1)
├── (folder 2)
├── (folder 3)
└── (folder 4)

X:\SetupFiles\                     ← 3 post-setup files
├── unattend.xml
├── post-setup-tweaks.ps1
└── post-setup-combo.ps1
```

**Explanation:**
- **Portable apps** are called directly from `X:\Softwares` when WinPE is active
- **When running OS install task:** At the end of the process, `next-step-{}.ps1` will be called
- **next-step.ps1** will inject files from `X:\SetupFiles` into the new OS

### 3.3 Edit winpeshl.ini

The `winpeshl.ini` file determines which program runs when WinPE starts.

Process: WinPE boots → `Winpeshl.exe` reads `winpeshl.ini` → Calls applications in order.

**Note:** `coresystem-ng.exe` file must be in `X:\Windows\System32`

```ini
[LaunchApps]
%windir%\system32\wpeutil.exe,InitializeNetwork
%windir%\system32\coresystem-ng.exe
```

### 3.4 Unmount /commit

```powershell
# Close all windows accessing mount directory before proceeding
Dism /Unmount-Wim /MountDir:"C:\Boot" /Commit
```

---

## Checklist

### Prerequisites
- [ ] Windows 11 (24H2/25H2)
- [ ] PowerShell 7.6 installed
- [ ] USB drive (8GB+) ready
- [ ] Windows 11 ISO downloaded

### Create WinPE
- [ ] OSDeploy module installed
- [ ] OSDCloud module installed
- [ ] Prerequisites installed
- [ ] Drivers updated (1st time)
- [ ] Windows 11 ISO imported
- [ ] Drivers updated (2nd time - WiFi)
- [ ] WinPE built successfully
- [ ] ISO generated (~1.3GB)

### Customization
- [ ] Mount directory created
- [ ] boot.wim mounted
- [ ] Files copied correctly
- [ ] winpeshl.ini configured
- [ ] Unmount /commit successful

### Testing
- [ ] USB created with Rufus
- [ ] Test boot successful
- [ ] CoreSystem launches correctly

---

## Q&A

### Why update drivers twice?

**1st time:** OSDeploy downloads drivers from Internet (Dell/HP/Microsoft...)

**2nd time:** After importing ISO, WinRE already has WiFi drivers integrated

**Purpose:** Ensures WinPE has enough drivers for most devices

---

### Can I use virtual machine to build?

**No,** building on virtual machine will be rejected.

**Solution:** Use physical machine or apply tweaks to bypass.

---

### Unmount /commit fails with error?

**Cause:** A window or application is accessing the mount directory.

**Solution:** Close all related windows, then Unmount /discard and redo.

---

### Apps don't run correctly, what to check?

Check the following items:

1. **File structure** - Are files copied to correct locations?
2. **winpeshl.ini** - Is it configured correctly?
3. **coresystem.exe file** - Is it in System32?

---

### How big is the ISO file?

- **PowerShell version:** ~1.1GB
- **Binary version:** ~1.3GB

---

### How many attempts before success?

New users typically need **2-3 attempts** before getting a usable result.

This is normal process, don't give up!

---

### Can I customize the Binary version?

**Limited.** Binary version is already self-contained.

For deep customization, use the **PowerShell version**.

---

### Where can I get help?

- **GitHub Issues:** Report bugs and suggestions
- **Community:** Peer support

**Note:** Project follows open-source philosophy with limited direct support.

---

## Download

- **Release:** https://github.com/coresystemvn/OSD.Project/releases
