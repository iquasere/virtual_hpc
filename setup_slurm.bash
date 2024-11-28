#Run from SMS node

## Variables definition
sms_name=hostname
sms_ip=$(hostname -I | awk '{print $1}')  # Assuming the first IP is the internal one
sms_eth_internal=eth0
eth_provision=eth1
internal_network=
internal_netmask=255.255.255.0
ntp_server=pool.ntp.centos.org
bmc_username=admin
bmc_password=p@ssw0rd
num_computes=4
c_ip=("192.168.10.11" "192.168.10.12" "192.168.10.13" "192.168.10.14")
c_bmc=("192.168.11.11" "192.168.11.12" "192.168.11.13" "192.168.11.14")
c_mac=()
c_name=("compute1" "compute2" "compute3" "compute4")
compute_regex=compute*
compute_prefix=compute

## Install base OS
echo ${sms_ip} ${sms_name} >> /etc/hosts
#systemctl disable firewalld        # firewall not running
#systemctl stop firewalld           # firewall not running
#dnf install http://repos.openhpc.community/OpenHPC/3/EL_9/aarch64/ohpc-release-3-1.el9.aarch64.rpm     # the rocky image is x86_64 (AMD), not aarch64 (ARM)
# also, to check the linux distro: cat /etc/os-release 
sudo dnf -y install http://repos.openhpc.community/OpenHPC/3/EL_9/x86_64/ohpc-release-3-1.el9.x86_64.rpm
dnf -y install dnf-plugins-core
dnf config-manager --set-enabled crb
dnf -y install ohpc-base
dnf -y install ohpc-warewulf
dnf -y install hwloc-ohpc
#systemctl enable chronyd.service        # chrony is installed with one of the previous three commands
#echo "local stratum 10" >> /etc/chrony.conf
#echo "server ${ntp_server}" >> /etc/chrony.conf
#echo "allow all" >> /etc/chrony.conf
#systemctl restart chronyd
timedatectl set-ntp true            # this is the only way to enable ntp
dnf -y install ohpc-slurm-server
cp /etc/slurm/slurm.conf.ohpc /etc/slurm/slurm.conf
cp /etc/slurm/cgroup.conf.example /etc/slurm/cgroup.conf
perl -pi -e "s/SlurmctldHost=\S+/SlurmctldHost=${sms_name}/" /etc/slurm/slurm.conf

# Warewulf configuration
perl -pi -e "s/device = eth1/device = ${sms_eth_internal}/" /etc/warewulf/provision.conf
ip link set dev ${sms_eth_internal} up
ip address add ${sms_ip}/${internal_netmask} broadcast + dev ${sms_eth_internal}
systemctl enable httpd.service
systemctl restart httpd
systemctl enable dhcpd.service
systemctl enable tftp.socket
systemctl start tftp.socket
export CHROOT=/opt/ohpc/admin/images/rocky9.3
wwmkchroot -v rocky-9 $CHROOT
dnf -y --installroot $CHROOT install epel-release
cp -p /etc/yum.repos.d/OpenHPC*.repo $CHROOT/etc/yum.repos.d

# Add openHPC components
dnf -y --installroot=$CHROOT install ohpc-base-compute
cp -p /etc/resolv.conf $CHROOT/etc/resolv.conf
cp /etc/passwd /etc/group $CHROOT/etc       # prompted to overwrite passwd and group files
dnf -y --installroot=$CHROOT install ohpc-slurm-client
chroot $CHROOT systemctl enable munge       # complained /proc/ not mounted
chroot $CHROOT systemctl enable slurmd      # complained /proc/ not mounted
echo SLURMD_OPTIONS="--conf-server ${sms_ip}" > $CHROOT/etc/sysconfig/slurmd
dnf -y --installroot=$CHROOT install chrony
echo "server ${sms_ip} iburst" >> $CHROOT/etc/chrony.conf
dnf -y --installroot=$CHROOT install kernel-`uname -r`      # can't find kernel-5.15.167.4-microsoft-standard-WSL2 - maybe dont need to install kernel drivers?
dnf -y --installroot=$CHROOT install lmod-ohpc
wwinit database
dnf install openssh
wwinit ssh_keys         # requires the previous command
echo "${sms_ip}:/home /home nfs nfsvers=4,nodev,nosuid 0 0" >> $CHROOT/etc/fstab                # these are for the nodes. Maybe all with $CHROOT are for the nodes?
echo "${sms_ip}:/opt/ohpc/pub /opt/ohpc/pub nfs nfsvers=3,nodev 0 0" >> $CHROOT/etc/fstab
echo "/home *(rw,no_subtree_check,fsid=10,no_root_squash)" >> /etc/exports
echo "/opt/ohpc/pub *(ro,no_subtree_check,fsid=11)" >> /etc/exports
exportfs -a
systemctl restart nfs-server
systemctl enable nfs-server





