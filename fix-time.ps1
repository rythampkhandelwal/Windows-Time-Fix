param (
    [Parameter(Position = 0)]
    [string]$Action
)

# Self-elevate to Administrator if not already running as Admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Elevating to Administrator privileges..." -ForegroundColor Yellow
    $argList = "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`""
    if ($Action) { $argList += " `"$Action`"" }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    Exit
}

function Invoke-TimeSync {
    Write-Host "`n--- [1] Synchronizing Clock ---" -ForegroundColor Cyan
    
    Write-Host "Fetching internet time from Google..." -ForegroundColor Gray
    try {
        $response = Invoke-WebRequest -Uri "https://www.google.com" -Method Head -UseBasicParsing -TimeoutSec 5
        $dateStr = $response.Headers.Date
        if ($dateStr) {
            $parsedDate = [DateTimeOffset]::Parse($dateStr).LocalDateTime
            Set-Date -Date $parsedDate | Out-Null
            Write-Host "Successfully set time via HTTP date: $parsedDate" -ForegroundColor Green
        }
    } catch {
        Write-Warning "Could not fetch web time directly: $($_.Exception.Message)"
    }

    Write-Host "Triggering Windows Time Service resync..." -ForegroundColor Gray
    try {
        if ((Get-Service w32time -ErrorAction SilentlyContinue).Status -ne 'Running') {
            Start-Service w32time -ErrorAction SilentlyContinue
        }
        $resyncOutput = & w32tm /resync /force 2>&1
        Write-Host "$resyncOutput" -ForegroundColor Gray
    } catch {
        Write-Warning "w32tm resync encountered an issue: $($_.Exception.Message)"
    }

    Write-Host "`nCurrent System Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Green
}

function Install-TimeSetup {
    Write-Host "`n--- Configuring Windows Time Service ---" -ForegroundColor Cyan
    try {
        Set-Service w32time -StartupType Automatic
        Start-Service w32time -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" -Name "MaxPosPhaseCorrection" -Value 0xFFFFFFFF -Type DWord
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" -Name "MaxNegPhaseCorrection" -Value 0xFFFFFFFF -Type DWord
        & w32tm /config /manualpeerlist:"time.google.com,0x9 pool.ntp.org,0x9" /syncfromflags:manual /reliable:YES /update | Out-Null
        Restart-Service w32time
        Write-Host "Windows Time service configured with NTP servers (time.google.com, pool.ntp.org)." -ForegroundColor Green
    } catch {
        Write-Error "Failed to configure Windows Time service: $($_.Exception.Message)"
    }

    Write-Host "`n--- Registering Scheduled Task ---" -ForegroundColor Cyan
    $taskXml = @'
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <BootTrigger><Enabled>true</Enabled><Delay>PT5S</Delay></BootTrigger>
    <LogonTrigger><Enabled>true</Enabled><Delay>PT5S</Delay></LogonTrigger>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name='Microsoft-Windows-Kernel-Power'] and (EventID=107)]] or *[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and (EventID=1)]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
      <Delay>PT5S</Delay>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author"><UserId>S-1-5-18</UserId><RunLevel>HighestAvailable</RunLevel></Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <ExecutionTimeLimit>PT1M</ExecutionTimeLimit>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-WindowStyle Hidden -Command "try { $d = (Invoke-WebRequest -Uri 'https://www.google.com' -Method Head -UseBasicParsing -TimeoutSec 5).Headers.Date; if ($d) { Set-Date -Date ([DateTimeOffset]::Parse($d).LocalDateTime) } } catch {}; w32tm /resync /force"</Arguments>
    </Exec>
  </Actions>
</Task>
'@
    try {
        Register-ScheduledTask -TaskName "AutoSyncTimeOnWakeAndBoot" -Xml $taskXml -Force | Out-Null
        Write-Host "Scheduled task 'AutoSyncTimeOnWakeAndBoot' installed successfully (runs on boot, logon, and wake)." -ForegroundColor Green
    } catch {
        Write-Error "Failed to register scheduled task: $($_.Exception.Message)"
    }
}

function Uninstall-TimeSetup {
    Write-Host "`n--- Uninstalling AutoSync Configuration ---" -ForegroundColor Cyan
    $taskName = "AutoSyncTimeOnWakeAndBoot"
    try {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Write-Host "Removed scheduled task '$taskName'." -ForegroundColor Green
        } else {
            Write-Host "Scheduled task '$taskName' was not found." -ForegroundColor Yellow
        }
    } catch {
        Write-Warning "Could not remove scheduled task: $($_.Exception.Message)"
    }

    try {
        Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" -Name "MaxPosPhaseCorrection" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" -Name "MaxNegPhaseCorrection" -ErrorAction SilentlyContinue
        Restart-Service w32time -ErrorAction SilentlyContinue
        Write-Host "Phase correction registry settings reverted." -ForegroundColor Green
    } catch {
        Write-Warning "Could not revert registry settings: $($_.Exception.Message)"
    }

    Write-Host "`nUninstall completed successfully." -ForegroundColor Green
}

function Execute-Option ($opt) {
    switch ($opt) {
        "1" { Invoke-TimeSync }
        "2" {
            Install-TimeSetup
            Invoke-TimeSync
        }
        "3" { Install-TimeSetup }
        "4" { Uninstall-TimeSetup }
        default { Write-Warning "Unknown option: $opt" }
    }
}

# If an action was passed as an argument, run it directly
if ($Action) {
    Execute-Option $Action
    Exit
}

# Interactive Menu Loop
do {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "             Windows Time Fixer             " -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  1 - Sync" -ForegroundColor White
    Write-Host "  2 - Setup and Run" -ForegroundColor White
    Write-Host "  3 - Setup" -ForegroundColor White
    Write-Host "  4 - Uninstall" -ForegroundColor White
    Write-Host "  Q - Exit" -ForegroundColor Gray
    Write-Host "============================================" -ForegroundColor Cyan

    $selection = (Read-Host "Select an option (1-4 or Q)").Trim()

    if ($selection -in '1', '2', '3', '4') {
        Execute-Option $selection
        Write-Host ""
        Read-Host "Press Enter to return to menu..."
    } elseif ($selection -in 'q', 'quit', 'exit') {
        Write-Host "Exiting..." -ForegroundColor Gray
        break
    } else {
        Write-Warning "Invalid option '$selection'. Please choose 1, 2, 3, 4, or Q."
    }
} while ($true)
