### Quick start guide [hướng dẫn nhanh]

1. Theo quy trình 5 bước của [OSDeploy](https://www.osdeploy.com) để tạo đĩa PE cơ bản với đủ driver cùng OSDCloud và các gói hỗ trợ được nhúng sãn
2. Quy trình 4 bước copy bộ source powershell của [CoreSystem](https://coresystem.vn) vào WinPE gồm
- Mount boot.wim (file đã tạo ra từ bước 1)
- Copy chương trình theo cấu trúc thư mục gợi ý gồm chương trình chính (coresystem.ps1 hoặc coresystem-ng.ps1), SetupFiles (các file hậu cài đặt để tối ưu Windows cũng như cài đặt ứng dụng tự động), Softwares (các ứng dụng phần mềm portable hỗ trợ như các công cụ cứu hộ)
- Chỉnh sửa thông tin startnet.cmd để thiết lập chạy chương trình chính tự động
- Unmount boot.wim /commit => lưu lại các thiết lập
3. Gọi lệnh powershell `Update-OSDeployBootISO` để hoàn tất. Dùng rufus ghi vào vào USB sẵn sàng sử dụng

### Hướng dẫn chuyên sâu

Tham khảo tại trang wiki của dự án [OSD.Project](https://github.com/coresystemvn/OSDCloud/wiki)



