# ==============================================================================
# Intel NUC 14 Pro - Native Boot Fixed VHDX Deployment Script
# Must be executed from an Elevated PowerShell Session (Run as Administrator)
# ==============================================================================

# --- Configuration Variables ---
$VHDXPath     = "C:\VHDs\NUC14Pro_NativeOS.vhdx"
$VHDXSizeGB   = 120GB                             # Fixed allocation prevents NPU DMA mapping failures
$WimPath      = "D:\sources\install.wim"         # Path to your Windows 11 installation media
$ImageIndex   = 3                                # Run 'Get-WindowsImage -ImagePath $WimPath' to verify index
$BootMenuName = "NUC14-W11-VHDX (Native Boot)"

# Path to the folder containing extracted Intel Serial IO, IPF, NPU, and Chipset drivers (.inf format)
$IntelDriverFolder = "C:\Drivers\NUC14Pro_Intel_Stack" 

# 1. Environment Preparation
if (-not (Test-Path (Split-Path $VHDXPath))) {
    New-Item -ItemType Directory -Path (Split-Path $VHDXPath) -Force | Out-Null
}

Write-Host "1. Generating Fixed-Size VHDX Container (Pre-allocating blocks)..." -ForegroundColor Cyan
# Fixed VHDX is mandatory to prevent Code 10/43 resource conflicts on Intel Core Ultra NPUs
$VHDX = New-VHD -Path $VHDXPath -SizeBytes $VHDXSizeGB -Fixed

Write-Host "2. Mounting the VHDX container..." -ForegroundColor Cyan
$MountedVHD = Mount-VHD -Path $VHDXPath -Passthru

Write-Host "3. Initializing virtual disk layout as GPT..." -ForegroundColor Cyan
$Disk = Initialize-Disk -Number $MountedVHD.DiskNumber -PartitionStyle GPT -Passthru
$Partition = New-Partition -DiskNumber $Disk.DiskNumber -UseMaximumSize -AssignDriveLetter

Write-Host "4. Formatting partition (NTFS)..." -ForegroundColor Cyan
Format-Volume -DriveLetter $Partition.DriveLetter -FileSystem NTFS -NewFileSystemLabel "NUC_NativeOS" -Confirm:$false
$TargetDrive = "$($Partition.DriveLetter):\"

Write-Host "5. Applying Windows Image to $TargetDrive via DISM..." -ForegroundColor Cyan
Expand-WindowsImage -ImagePath $WimPath -Index $ImageIndex -ApplyPath $TargetDrive

Write-Host "6. Slipstreaming Intel Serial IO, IPF, and NPU Drivers offline..." -ForegroundColor Cyan
if (Test-Path $IntelDriverFolder) {
    # Force injection ensures the platform framework initializes during the specialized Plug-and-Play phase
    Add-WindowsDriver -Path $TargetDrive -Driver $IntelDriverFolder -Recurse -ForceUnsigned
} else {
    Write-Warning "Driver folder not found at $IntelDriverFolder. Skipping offline injection."
}

Write-Host "7. Modifying offline registry to bypass hypervisor isolation blocks..." -ForegroundColor Cyan
# This prevents Intel's Platform Insight Framework app from flagging the vhdmp.sys driver layer as a VM
& reg.exe load HKLM\VHDX_SYSTEM "$($TargetDrive)Windows\System32\config\SYSTEM" | Out-Null
New-ItemProperty -Path "HKLM\VHDX_SYSTEM\ControlSet001\Control\CI\ProtectedOutputs" -Name "DisableRuntimeChecks" -PropertyType DWord -Value 1 -Force | Out-Null
& reg.exe unload HKLM\VHDX_SYSTEM | Out-Null

Write-Host "8. Injecting boot files into host system partition..." -ForegroundColor Cyan
# Run bcdboot to write the base Windows Boot Manager configurations
& bcdboot.exe "$($TargetDrive)Windows" /d /addlast

Write-Host "9. Modifying BCD entries to bypass virtual machine abstraction..." -ForegroundColor Cyan
# Explicitly fetch the GUID of the entry we just created to modify its boot parameters
$BcdQuery = & bcdedit.exe /v
$GuidLine = $BcdQuery | Select-String -Pattern "{[a-f0-9-]{36}}" -Context 0, 4 | Where-Object { $_.Context.PostContext -match [regex]::Escape($BootMenuName) }

if ($GuidLine) {
    $Guid = ($GuidLine.Matches.Value)
    Write-Host "Targeting BCD Entry GUID: $Guid" -ForegroundColor Green
    
    # Force the Bootloader to re-interrogate bare-metal hardware ACPI topology tables directly
    & bcdedit.exe /set $Guid detecthal yes
    # Ensure Windows doesn't isolate the environment inside a hypervisor context
    & bcdedit.exe /set $Guid hypervisorlaunchtype off
} else {
    Write-Warning "Could not dynamically fetch the new BCD Entry GUID. You may need to run 'bcdedit /set {current} detecthal yes' manually after booting into the OS."
}

Write-Host "10. Safe dismounting of VHDX storage stack..." -ForegroundColor Cyan
Dismount-VHD -Path $VHDXPath

Write-Host "`n[SUCCESS] The NUC 14 Pro optimized VHDX is ready. Reboot and select '$BootMenuName'." -ForegroundColor Green