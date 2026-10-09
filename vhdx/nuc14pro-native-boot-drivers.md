

The primary requirement for the Core Ultra (Meteor Lake / NPU-enabled) architecture is ensuring the platform framework drivers are bound to the hardware during the initial offline Plug-and-Play (PnP) image pass. 
Without these, the virtual disk manager layer (vhdmp.sys) initializes before the system ACPI stack can map direct DMA channels to the NPU coprocessor, leading to platform framework errors. 

Core Drivers to Add (C:\Drivers\NUC14Pro_Intel_Stack)

Place the extracted contents of the following official driver packages inside subfolders within your path (DISM’s -Recurse flag will automatically traverse them):
1. Intel AI Boost / NPU Driver
Package Name: Intel NPU Driver for Windows 11   Target Device: PCI\VEN_8086&DEV_7D1D   Key INF Files: IntelNPU.inf / npudriver.inf
Why It’s Needed: Provides direct DMA channel mapping for the neural engine.
Offline injection prevents Windows from assigning a default fallback driver during first boot.

2. Intel Innovation Platform Framework (IPF)
Package Name: Intel Innovation Platform Framework Manager   Target Device: ACPI\VEN_INTC&DEV_1042 and PCI\VEN_8086&DEV_7D03Key INF Files: ipf_cpu.inf, ipf_enum.inf, ipf_core.inf
Why It’s Needed: The core engine that Intel's Platform Insight software queries for thermal, power, and hardware topology.
Injecting this ensures the system identifies as bare-metal rather than a virtual machine.3. Intel Serial IO Host ControllerPackage Name: Intel Serial IO Driver   Target Device: ACPI\VEN_INTC&DEV_1083 and PCI\VEN_8086&DEV_7E23Key INF Files: iaLPSS2_i2c_mtl.inf, iaLPSS2_gpio2_mtl.inf, iaLPSS2_spi_mtl.infWhy It’s Needed: Exposes high-speed low-power IC channels (GPIO, I2C, SPI) to the OS before user mode services load.4. Intel Chipset Device SoftwarePackage Name: Intel Chipset Device Software   Target Device: PCI\VEN_8086&DEV_7E22 (SMBus, PCIe Root Ports, ACPI infrastructure)   Key INF Files: MeteorLakeSystem.inf, MeteorLakePchSystem.infWhy It’s Needed: Installs base INF configurations for internal bus routing, preventing unidentified "PCI Data Acquisition" devices in Device Manager.5. Intel Gaussian and Neural Accelerator (GNA)Package Name: Intel GNA Scoring Accelerator   Target Device: PCI\VEN_8086&DEV_7E4C   Key INF Files: gna.infWhy It’s Needed: Handles low-power audio and continuous background inference offloading.How to Extract Them CleanlyIf the driver download from ASUS or Intel is provided as an .exe file (such as SetupNPU.exe or SetupIPF.exe), extract the raw INFs using 7-Zip or via the command line:PowerShell# Example: Extracting executable installers into raw INF directories

SetupNPU.exe -extract "C:\Drivers\NUC14Pro_Intel_Stack\NPU"
SetupIPF.exe /x:"C:\Drivers\NUC14Pro_Intel_Stack\IPF"

Alternatively, download the ASUS NUC 14 Pro Driver Pack (.zip) directly from the ASUS support page.
Unzip it and copy the driver subfolders straight into C:\Drivers\NUC14Pro_Intel_Stack\ prior to executing the VHDX deployment script.

[=======================================================================================================================================================================================================================]

Injecting the IPF (Innovation Platform Framework) driver stack offline solves the low-level platform barrier. IPF is the modern core architecture (introduced starting with 12th/13th Gen and continued through Core Ultra / Meteor Lake) that replaced legacy DTT drivers. It exposes the hardware thermal sensors, ACPI power tables, and system topology directly to the OS kernel without getting blocked by the vhdmp.sys storage layer.

However, for full DTT dynamic power capping and thermal polling to function active end-to-end, you need to handle both layers:

1. Kernel/Hardware Layer (Handled by your script)
IPF Drivers + Registry Hook (DisableRuntimeChecks): Passing the ACPI/PCI nodes to the kernel and disabling Protected Outputs runtime checks allows the lower-level hardware drivers to initialize without flagging the virtual disk boot path as an unsupported hypervisor/VM context.

detecthal yes: Forces the bootloader to query the physical ACPI tables directly for thermal zones and power states.

2. User-Mode Telemetry & Service Layer (Post-First-Boot Requirement)
DTT relies on background user-mode services and local telemetry apps (such as the Intel Innovation Platform Framework Service / ipf_helper.exe and the Intel Application Optimization / APO service) to dynamically adjust power limits (PL1/PL2/PL4) and poll sensor data in real time.

Because DISM offline injection (Add-WindowsDriver) only stages the driver INF and sys files into the Driver Store, the user-mode service components and scheduled tasks do not fully register until the OS boots live.

What to do after first boot into the VHDX:
Once you boot into the Native OS image for the first time:

Open Services (services.msc) and confirm that Intel Innovation Platform Framework Service is present and set to Automatic (Started).

If the service is missing or disabled, run the official Intel IPF / DTT setup package executable once from inside the booted VHDX environment. This registers the background monitoring service and telemetry RPC endpoints that communicate with the driver stack you slipstreamed.

Once that service is running live, DTT will poll hardware sensors, adjust thermal throttling points, and manage Core Ultra power states as if Windows were installed on a standard physical partition.