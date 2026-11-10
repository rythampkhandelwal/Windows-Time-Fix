# Windows Time Fixer (`fix-time.ps1`)

A robust PowerShell utility to resolve Windows clock drift, desync issues (common in dual-boot systems, dead CMOS batteries, or after waking from sleep), and configure automated background time synchronization.

---

## 🚀 Features

- **Dual-Method Synchronization**:
  - Direct HTTP time sync via Google headers (bypasses ISP/firewall NTP blocks).
  - Native Windows Time Service (`w32tm`) resync with public NTP servers.
- **Automated Background Sync**:
  - Automatically syncs the clock on **System Boot**, **User Logon**, and **Wake from Sleep** (via Event Triggers `Kernel-Power` 107 & `Power-Troubleshooter` 1).
- **Phase Correction Fix**:
  - Removes the Windows phase correction limits (`MaxPosPhaseCorrection` and `MaxNegPhaseCorrection`), allowing the clock to snap to the correct time even if the difference is several hours or days.
- **Admin Self-Elevation**: Automatically requests Administrator privileges if opened in a standard user session.
- **Interactive Menu & CLI Support**: Run with an interactive numbered menu or automate via command-line arguments.

---

## 📋 Menu Options

When executed, the script displays the following options:

| Option | Name | Description |
| :---: | :--- | :--- |
| **`1`** | **Sync** | Immediately synchronizes the clock using both HTTP and `w32tm` without changing persistent system settings. |
| **`2`** | **Setup and Run** | Full installation: sets service to Automatic, configures NTP servers, installs the background wake/boot scheduled task, and immediately syncs the clock. *(Recommended for first-time use)* |
| **`3`** | **Setup** | Applies service configuration and installs the background scheduled task without performing an immediate sync. |
| **`4`** | **Uninstall** | Removes the scheduled task (`AutoSyncTimeOnWakeAndBoot`) and restores default phase correction settings. |
| **`Q`** | **Exit** | Closes the menu. |

---

## 💻 How to Use

### Method 1: Right-Click (Quickest)
1. Right-click on the file.
2. Select **Run with PowerShell**.
3. Accept the User Account Control (UAC) prompt if requested.
4. Type your option (`1`, `2`, `3`, or `4`) and press **Enter**.

---

### Method 2: PowerShell Console
Open an elevated PowerShell window and navigate to your Desktop:

```powershell
cd "path\to\fix-time.ps1"
.\fix-time.ps1
```

### Method 3: Non-Interactive / Automation
You can pass the option directly as an argument:

```powershell
# Sync clock immediately
.\fix-time.ps1 1

# Setup and sync immediately
.\fix-time.ps1 2

# Setup only
.\fix-time.ps1 3

# Uninstall background task
.\fix-time.ps1 4
```

---

## 🔍 How It Works

1. **HTTP Date Sync**:
   Issues a lightweight `HEAD` request to `https://www.google.com` to grab the server's RFC-1123 date header and calls `Set-Date`. This provides instant recovery even if local NTP ports (UDP 123) are blocked.
2. **NTP Servers Configured**:
   - `time.google.com,0x9`
   - `pool.ntp.org,0x9`
3. **Registry Tweaks**:
   - `HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config\MaxPosPhaseCorrection = 0xFFFFFFFF`
   - `HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config\MaxNegPhaseCorrection = 0xFFFFFFFF`
4. **Scheduled Task**:
   Registers `AutoSyncTimeOnWakeAndBoot` under the `SYSTEM` account (`S-1-5-18`) with highest privileges so no password is required.

---

## 🗑️ Uninstallation

Select option **`4 - Uninstall`** from the menu or run:
```powershell
.\fix-time.ps1 4
```
This safely removes the scheduled task and clears the registry overrides.
