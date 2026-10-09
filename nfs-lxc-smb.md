
# __SHARE SMB FROM LXC VIA NFS SOURCE__ #

# Step 1: On the NFS Archive Server (The Source)
Export the /opt/glftpd/site directory to your Proxmox host IP.

- Edit /etc/exports:
sudo nano /etc/exports

- Add your export rule (replace 192.168.1.5 with your Proxmox host IP):
/opt/glftpd/site  192.168.1.5(rw,sync,no_subtree_check,no_root_squash)

- Apply and verify:
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
sudo showmount -e localhost


# Step 2: On the Proxmox Host (pve)
Mount the NFS share locally on Proxmox, create the LXC container, and attach the share.

- Test and persist the NFS mount on the Proxmox host:
mkdir -p /mnt/pve-nfs-site
mount -t nfs 192.168.1.100:/opt/glftpd/site /mnt/pve-nfs-site

- Add to /etc/fstab on Proxmox so it remounts automatically on boot:
192.168.1.100:/opt/glftpd/site  /mnt/pve-nfs-site  nfs  defaults,noatime,_netdev  0  0

- Create the Unprivileged LXC Container (ID 110):
pct create 110 local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst \
  --ostype ubuntu \
  --hostname samba-lxc \
  --cores 2 \
  --memory 1024 \
  --swap 512 \
  --features nesting=1,keyctl=1 \
  --unprivileged 1 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --storage local-lld

- Bind-mount the host's NFS folder into the LXC container:
pct set 110 -mp0 /mnt/pve-nfs-site,mp=/mnt/site

- Start the container:
pct start 110


# Step 3: Inside LXC Container 110 (The Samba Server)
Log in to the container (pct enter 110) and configure Samba.

- Verify the files are visible inside the container:
ls -la /mnt/site
(You should see your /opt/glftpd/site files directly at /mnt/site.)

- Install Samba:
apt update && apt install -y samba

- Configure /etc/samba/smb.conf:
nano /etc/samba/smb.conf

- Append the share configuration at the bottom:
[site]
   path = /mnt/site
   browseable = yes
   read only = yes
   guest ok = no
   force user = cifs

- Create a Samba user:
smbpasswd -a smbuser

- Restart Samba:
systemctl restart smbd