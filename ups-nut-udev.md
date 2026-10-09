
## CyberPower UPS - UDEV Rules ##

The solution is to bind each UPS to its specific physical USB port using Linux udev rules or physical USB path targeting, rather than relying on serial numbers.

## Option 1: Target by Physical USB Port Path in NUT (Cleanest Solution)
If you are using NUT (Network UPS Tools), the usbhid-ups driver natively supports matching devices by their physical USB topology path (bus) rather than serial numbers.

Find the physical USB paths:
Run lsusb -t or check dmesg when plugging them in. You will see which physical port each unit occupies (e.g., Bus 01 Port 02 vs Bus 01 Port 03).

Configure /etc/nut/ups.conf:
Use the bus or port parameters along with vendorid and productid instead of serial numbers:

[ups-a]
    driver = usbhid-ups
    port = auto
    vendorid = 0764
    productid = 0501
    bus = "001/002"  # Match physical USB Bus and Device path
    desc = "CyberPower UPS A"

[ups-b]
    driver = usbhid-ups
    port = auto
    vendorid = 0764
    productid = 0501
    bus = "001/003"  # Match second physical USB path
    desc = "CyberPower UPS B"

## Option 2: Use udev Rules to Create Unique Symlinks
If NUT or another tool needs static paths, create udev rules tied strictly to the physical USB port topology.

Get the physical kernel path:
Unplug UPS B, keep UPS A plugged in, and run:

udevadm info -a -n /dev/bus/usb/001/002 | grep "KERNELS=="
Look for the parent port path line (e.g., KERNELS=="1-1.2" vs KERNELS=="1-1.3").

Create a custom udev rule (/etc/udev/rules.d/99-ups.rules):

# UPS A - Plugged into USB Port 1-1.2
SUBSYSTEM=="usb", ATTR{idVendor}=="0764", ATTR{idProduct}=="0501", KERNELS=="1-1.2", SYMLINK+="ups-a", MODE="0666"

# UPS B - Plugged into USB Port 1-1.3
SUBSYSTEM=="usb", ATTR{idVendor}=="0764", ATTR{idProduct}=="0501", KERNELS=="1-1.3", SYMLINK+="ups-b", MODE="0666"
Reload udev rules:

sudo udevadm control --reload-rules
sudo udevadm trigger
Now /dev/ups-a and /dev/ups-b will always point to the correct physical unit regardless of boot order—just make sure you don't swap the cables on the back of the machine!