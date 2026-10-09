# ==============================================================================
# Intel NUC 14 Pro - Native Boot Partitioned VHDX Deployment Script
# Engine: Native Diskpart (Zero Hyper-V / WMI Dependency)
# Must be executed from an Elevated PowerShell Session (Run as Administrator)
# ==============================================================================

# --- Configuration Variables ---
$VHDXPath          = "C:\VHDs\NUC14Pro_NativeOS.vhdx"
$VHDXSizeMB        = 122880                                # 120GB in MB for Diskpart
$WimPath           = "D:\sources\install.wim"             # Path to Windows 11 installation media
$ImageIndex        = 3                                     # Run 'Get-WindowsImage -ImagePath $WimPath' to verify index
$BootMenuName      = "NUC14-W11-VHDX (Native Boot)"

# Path to folder containing extracted Intel Serial IO, IPF, NPU, and Chipset drivers (.inf format)
$IntelDriverFolder = "C:\Drivers\NUC14Pro_Intel_Stack" 

# Track state for cleanup routine in case of failure
$Script:VHDXMounted     = $false
$Script:RegHiveLoaded    = $false
$Script:EfiDriveLetter   = $null
$Script:OSDriveLetter    = $null
$Script:RecDriveLetter   = $null

# Force script to halt on errors to trigger catch/finally blocks
$ErrorActionPreference = "Stop"

try {
    # --------------------------------------------------------------------------
    # 1. Environment Preparation & VHDX Creation via Diskpart
    # --------------------------------------------------------------------------
    if (-not (Test-Path (Split-Path $VHDXPath))) {
        New-Item -ItemType Directory -Path (Split-Path $VHDXPath) -Force | Out-Null
    }

    Write-Host "1. Creating and Mounting Fixed-Size VHDX via Diskpart..." -ForegroundColor Cyan
    $CreateScript = @"
create vdisk file="$VHDXPath" maximum=$VHDXSizeMB type=fixed
attach vdisk
"@
    $CreateScript | diskpart.exe | Out-Null
    $Script:VHDXMounted = $true

    # Fetch disk number of the mounted virtual disk
    Start-Sleep -Seconds 2
    $MountedDisk = Get-Disk | Where-Object { $_.Location -like "*$VHDXPath*" -or $_.Model -eq "Virtual Disk" } | Select-Object -Last 1
    if (-not $MountedDisk) { throw "Failed to identify mounted VHDX disk number." }
    $DiskNum = $MountedDisk.Number

    # --------------------------------------------------------------------------
    # 2. Disk Initialization & Partition Layout
    # --------------------------------------------------------------------------
    Write-Host "2. Initializing GPT Disk Layout & Partitions on Disk $DiskNum..." -ForegroundColor Cyan
    Initialize-Disk -Number $DiskNum -PartitionStyle GPT -Confirm:$false | Out-Null

    Write-Host " Creating EFI System Partition (1GB)..." -ForegroundColor Gray
    $EfiPart = New-Partition -DiskNumber $DiskNum -Size 1GB -GptType "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" -AssignDriveLetter
    $Script:EfiDriveLetter = $EfiPart.DriveLetter

    Write-Host " Creating Microsoft Reserved (MSR) Partition (16MB)..." -ForegroundColor Gray
    New-Partition -DiskNumber $DiskNum -Size 16MB -GptType "{e3c9e316-0b5c-4db8-817d-f92df00215ae}" | Out-Null

    Write-Host " Creating Primary OS Partition..." -ForegroundColor Gray
    $OSPart = New-Partition -DiskNumber $DiskNum -UseMaximumSize -GptType "{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}" -AssignDriveLetter
    $Script:OSDriveLetter = $OSPart.DriveLetter

    Write-Host " Creating Recovery Partition (1GB)..." -ForegroundColor Gray
    $RecPart = New-Partition -DiskNumber $DiskNum -Size 1GB -GptType "{de94bba4-06d1-4d40-a16a-bfd50179d6ac}" -AssignDriveLetter
    $Script:RecDriveLetter = $RecPart.DriveLetter

    # --------------------------------------------------------------------------
    # 3. Formatting Volumes
    # --------------------------------------------------------------------------
    Write-Host "3. Formatting Volumes..." -ForegroundColor Cyan
    Format-Volume -DriveLetter $Script:EfiDriveLetter -FileSystem FAT32 -NewFileSystemLabel "VHD_SYSTEM" -Confirm:$false | Out-Null
    Format-Volume -DriveLetter $Script:OSDriveLetter  -FileSystem NTFS  -NewFileSystemLabel "NUC_NativeOS" -Confirm:$false | Out-Null
    Format-Volume -DriveLetter $Script:RecDriveLetter -FileSystem NTFS  -NewFileSystemLabel "Recovery"     -Confirm:$false | Out-Null

    $EfiDrive = "$($Script:EfiDriveLetter):"
    $OSDrive  = "$($Script:OSDriveLetter):\"
    $RecDrive = "$($Script:RecDriveLetter):\"

    # --------------------------------------------------------------------------
    # 4. Image Deployment & Driver Injection
    # --------------------------------------------------------------------------
    Write-Host "4. Applying Windows Image to $OSDrive via DISM..." -ForegroundColor Cyan
    Expand-WindowsImage -ImagePath $WimPath -Index $ImageIndex -ApplyPath $OSDrive

    Write-Host "5. Slipstreaming Intel Driver Stack..." -ForegroundColor Cyan
    if (Test-Path $IntelDriverFolder) {
        $InfFiles = Get-ChildItem -Path $IntelDriverFolder -Filter "*.inf" -Recurse
        if ($InfFiles.Count -gt 0) {
            Write-Host "   Found $($InfFiles.Count) driver INF files. Injecting into offline image..." -ForegroundColor Gray
            Add-WindowsDriver -Path $OSDrive -Driver $IntelDriverFolder -Recurse -ForceUnsigned | Out-Null
        } else {
            Write-Warning "Driver directory exists but contains no .inf files! Ensure packages were extracted."
        }
    } else {
        Write-Warning "Driver folder not found at $IntelDriverFolder. Skipping offline injection."
    }

    # --------------------------------------------------------------------------
    # 5. Configure WinRE in Recovery Partition
    # --------------------------------------------------------------------------
    Write-Host "6. Configuring WinRE inside Recovery partition..." -ForegroundColor Cyan
    $SourceWinRE = Join-Path $OSDrive "Windows\System32\Recovery\WinRE.wim"
    $TargetDir   = Join-Path $RecDrive "Recovery\WindowsRE"
    $TargetWinRE = Join-Path $TargetDir "WinRE.wim"

    if (Test-Path $SourceWinRE) {
        if (-not (Test-Path $TargetDir)) {
            New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
        }

        Copy-Item -Path $SourceWinRE -Destination $TargetWinRE -Force
        & attrib.exe +h +s +r $TargetWinRE

        $ReagentResult = & reagentc.exe /setreimage /path $TargetDir /target "$($OSDrive)Windows" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Reagentc registration failed: $ReagentResult" }

        Remove-PartitionAccessPath -DiskNumber $DiskNum -PartitionNumber $RecPart.PartitionNumber -AccessPath $RecDrive
        Set-GPA -DiskNumber $DiskNum -PartitionNumber $RecPart.PartitionNumber -Attributes 0x8000000000000001 | Out-Null
        $Script:RecDriveLetter = $null

        Write-Host "   WinRE configured and recovery partition protected." -ForegroundColor Green
    } else {
        Write-Warning "WinRE.wim missing at $SourceWinRE. Skipping recovery setup."
    }

    # --------------------------------------------------------------------------
    # 6. Storage & Hardware Abstraction Registry Hooks
    # --------------------------------------------------------------------------
    Write-Host "7. Applying offline registry hooks..." -ForegroundColor Cyan
    $RegResult = & reg.exe load HKLM\VHDX_SYSTEM "$($OSDrive)Windows\System32\config\SYSTEM" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed to load offline registry hive: $RegResult" }
    $Script:RegHiveLoaded = $true

    New-ItemProperty -Path "HKLM\VHDX_SYSTEM\ControlSet001\Control\CI\ProtectedOutputs" -Name "DisableRuntimeChecks" -PropertyType DWord -Value 1 -Force | Out-Null
    Set-ItemProperty -Path "HKLM\VHDX_SYSTEM\ControlSet001\Services\stornvme" -Name "Start" -Value 0 -Force | Out-Null
    Set-ItemProperty -Path "HKLM\VHDX_SYSTEM\ControlSet001\Services\vhdmp" -Name "Start" -Value 0 -Force | Out-Null
    New-ItemProperty -Path "HKLM\VHDX_SYSTEM\ControlSet001\Control\FileSystem" -Name "DisableDeleteNotify" -PropertyType DWord -Value 0 -Force | Out-Null

    & reg.exe unload HKLM\VHDX_SYSTEM | Out-Null
    $Script:RegHiveLoaded = $false

    # --------------------------------------------------------------------------
    # 7. First-Boot OOBE Service Registration Script
    # --------------------------------------------------------------------------
    Write-Host "8. Staging SetupComplete script for Intel IPF service auto-start..." -ForegroundColor Cyan
    $SetupScriptDir = Join-Path $OSDrive "Windows\Setup\Scripts"
    if (-not (Test-Path $SetupScriptDir)) {
        New-Item -ItemType Directory -Path $SetupScriptDir -Force | Out-Null
    }
    $SetupScriptPath = Join-Path $SetupScriptDir "SetupComplete.cmd"
    $SetupCmdContent = "@echo off`r`nsc config esif_uf start= auto`r`nnet start esif_uf"
    Set-Content -Path $SetupScriptPath -Value $SetupCmdContent -Encoding Ascii -Force

    # --------------------------------------------------------------------------
    # 8. Configure Bootloader (Internal EFI & Host BCD Integration)
    # --------------------------------------------------------------------------
    Write-Host "9. Writing EFI boot files and registering with Host BCD..." -ForegroundColor Cyan
    $BcdBootInternal = & bcdboot.exe "$($OSDrive)Windows" /s $EfiDrive /f UEFI 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Internal BCDBoot failed: $BcdBootInternal" }

    $BcdBootHost = & bcdboot.exe "$($OSDrive)Windows" /d /addlast 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Host BCDBoot registration failed: $BcdBootHost" }

    Write-Host "10. Updating BCD parameters for direct ACPI pass-through..." -ForegroundColor Cyan
    $BcdQuery = & bcdedit.exe /v
    $GuidLine = $BcdQuery | Select-String -Pattern "{[a-f0-9-]{36}}" -Context 0, 4 | Where-Object { $_.Context.PostContext -match [regex]::Escape($BootMenuName) }

    if ($GuidLine) {
        $Guid = ($GuidLine.Matches.Value)
        Write-Host "   Targeting BCD Entry GUID: $Guid" -ForegroundColor Green
        & bcdedit.exe /set $Guid detecthal yes | Out-Null
        & bcdedit.exe /set $Guid hypervisorlaunchtype off | Out-Null
    } else {
        Write-Warning "Could not dynamically match BCD entry GUID. Verify 'detecthal' manually via bcdedit if needed."
    }

    Write-Host "`n[SUCCESS] NUC 14 Pro Native Boot VHDX deployment complete." -ForegroundColor Green

} catch {
    Write-Host "`n[ERROR] Script failed at line $($_.InvocationInfo.ScriptLineNumber):" -ForegroundColor Red
    Write-Host "$($_.Exception.Message)" -ForegroundColor Red

} finally {
    Write-Host "`n--- Cleanup Routine ---" -ForegroundColor Yellow

    if ($Script:RegHiveLoaded) {
        Write-Host "Unloading mounted registry hive..." -ForegroundColor Gray
        [gc]::Collect()
        & reg.exe unload HKLM\VHDX_SYSTEM | Out-Null
    }

    if ($Script:RecDriveLetter) {
        Write-Host "Cleaning up temporary recovery drive letter..." -ForegroundColor Gray
        Remove-PartitionAccessPath -DiskNumber $DiskNum -PartitionNumber$RecPart.PartitionNumber -AccessPath "$($Script:RecDriveLetter):\" -ErrorAction SilentlyContinue
    }

    if ($Script:VHDXMounted) {
        Write-Host "Dismounting VHDX via Diskpart..." -ForegroundColor Gray
        $DetachScript = @"
select vdisk file="$VHDXPath"
detach vdisk
"@
        $DetachScript | diskpart.exe | Out-Null
        Write-Host "VHDX cleanly dismounted." -ForegroundColor Gray
    }

    Write-Host "Cleanup routine finished." -ForegroundColor Yellow
}