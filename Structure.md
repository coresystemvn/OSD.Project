==== CORESYTEM | Advanced Windows Deployment System ====

### Folder structure [cấu trúc thư mục]

X:\SetupFiles [3 files]

    - unattend.xml
    - post-setup-tweaks.ps1
    - post-setup-combo.ps1

X:\Windows\System32 [4 files]

    - next-step-tweaks.ps1 [for TweaksOnly task flow]
    - next-step-combo.ps1 [for combo tweaks and apps task flow]
    - coresystem.ps1| coresystem-ng.ps1 [main system]
    - startnet.cmd [define startup sequence]

X:\Software [4 sub folders]

    - Explorer++
    - MultiDrive
    - HWInfo
    - Palemoon

X:\Program Files\WindowsPowerShell\Modules\OSDCloud\26.6.29.1 [OSDCloud modified version]

### Usage [Sử dụng]

#### System info

Information section short listed information Eg system firmware [UEFI], secureboot status and TPM status

#### Rescue Tools 
System rescue tools to check detailed system information (HWInfo64), backup data manually (Explorer++), backup full disk/partition (Multidrive) and browse the web (Palemoon)

#### Additional features

- Notepad (built-in)
- Powershell (built-in)
- Connect wifi
- Unlock Bitlocker encrypted drive

#### OS Deployment [main usage]

- Flow 1: clean install Windows (default Microsoft, no touch)
- Flow 2: clean install Windows (with business tweaks)
- Flow 3: clean install Windows (with business tweaks and basic softwares)

#### Advanced | Offline mode

- Main task will seek local drives for compatible .esd files from [Drive:]\OSDCloud\OS to install OS with-out internet connection
- Since the .esd files always bigger than 4GB, a NTFS formated drive is required
- Rufus can format boot drive with NTFS option. Otherwise, an additional drive to store local .esd files is required
- To download .esd files. We need dl-win-esd.sh [tool]

#### Next-gen version [bản đầy đủ hơn nâng cấp UI/UX]

coresystem-ng.ps1

Upgraded version with Wifi/Bitlocker UI/UX upgrade [100% XAML windows]
