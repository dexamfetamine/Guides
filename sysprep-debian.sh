
:: SYSPREP DEBIAN VM ::

# 1. Clear package caches and old logs
apt-get autoremove --purge -y
apt-get clean
find /var/log -type f -exec truncate --size=0 {} \;

# 2. Clear machine-id (crucial for unique DHCP leases on clones)
truncate -s 0 /etc/machine-id
rm /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

# 3. Regenerate SSH host keys on next boot (so clones aren't identical twins)
rm -f /etc/ssh/ssh_host_*
cat << 'EOF' > /etc/rc.local
#!/bin/sh -e
# Regenerate SSH host keys if they are missing
if ! ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1; then
    ssh-keygen -A
fi
exit 0
EOF
chmod +x /etc/rc.local

# 4. Clear command history and shut down immediately
history -c && history -w && poweroff