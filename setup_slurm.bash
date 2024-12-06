#Run from SMS node

## Variables definition
sms_name=`hostname`
sms_ip=$(hostname -I | awk '{print $1}')  # Assuming the first IP is the internal one
sms_eth_internal=10.0.8.1
eth_provision=enp0s8
internal_network=enp0s8
internal_netmask=255.255.255.0
ntp_server=pool.ntp.centos.org
bmc_username=admin
bmc_password=p@ssw0rd
num_computes=4
c_ip=("192.168.10.11" "192.168.10.12" "192.168.10.13" "192.168.10.14")
c_bmc=("192.168.11.11" "192.168.11.12" "192.168.11.13" "192.168.11.14")
c_mac=("08:00:27:9A:E7:B4" "08:00:27:E0:60:2E" "08:00:27:F0:F0:39" "08:00:27:67:CE:05")
c_name=("compute1" "compute2" "compute3" "compute4")
compute_regex=compute*
compute_prefix=compute

## Install base OS
echo ${sms_ip} ${sms_name} >> /etc/hosts
sudo systemctl disable firewalld
sudo systemctl stop firewalld
#sudo dnf install http://repos.openhpc.community/OpenHPC/3/EL_9/aarch64/ohpc-release-3-1.el9.aarch64.rpm     # the rocky image is x86_64 (AMD), not aarch64 (ARM)
# also, to check the linux distro: cat /etc/os-release 
sudo dnf -y install http://repos.openhpc.community/OpenHPC/3/EL_9/x86_64/ohpc-release-3-1.el9.x86_64.rpm
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --set-enabled crb
sudo dnf -y install ohpc-base
sudo dnf -y install ohpc-warewulf
sudo dnf -y install hwloc-ohpc               # /opt/ohpc/pub must be empty, or this fails - the shared_storage volume
sudo systemctl enable chronyd.service        # chrony is installed with one of the previous three commands
sudo echo "local stratum 10" >> /etc/chrony.conf
sudo echo "server ${ntp_server}" >> /etc/chrony.conf
sudo echo "allow all" >> /etc/chrony.conf
sudo systemctl restart chronyd           # fails with "adjtimex(0x8001) failed : Operation not permitted" - not on Linux server
#timedatectl set-ntp true            # this is the only way to enable ntp
sudo dnf -y install ohpc-slurm-server
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
sudo dnf -y --installroot $CHROOT install epel-release
cp -p /etc/yum.repos.d/OpenHPC*.repo $CHROOT/etc/yum.repos.d

# Add openHPC components
sudo dnf -y --installroot=$CHROOT install ohpc-base-compute
cp -p /etc/resolv.conf $CHROOT/etc/resolv.conf
cp /etc/passwd /etc/group $CHROOT/etc       # prompted to overwrite passwd and group files
sudo dnf -y --installroot=$CHROOT install ohpc-slurm-client
chroot $CHROOT systemctl enable munge       # complained /proc/ not mounted
chroot $CHROOT systemctl enable slurmd      # complained /proc/ not mounted
echo SLURMD_OPTIONS="--conf-server ${sms_ip}" > $CHROOT/etc/sysconfig/slurmd
sudo dnf -y --installroot=$CHROOT install chrony
echo "server ${sms_ip} iburst" >> $CHROOT/etc/chrony.conf
sudo dnf -y --installroot=$CHROOT install kernel-`uname -r`
sudo dnf -y --installroot=$CHROOT install lmod-ohpc
wwinit database
wwinit ssh_keys
echo "${sms_ip}:/home /home nfs nfsvers=4,nodev,nosuid 0 0" >> $CHROOT/etc/fstab
echo "${sms_ip}:/opt/ohpc/pub /opt/ohpc/pub nfs nfsvers=3,nodev 0 0" >> $CHROOT/etc/fstab
echo "/home *(rw,no_subtree_check,fsid=10,no_root_squash)" >> /etc/exports
echo "/opt/ohpc/pub *(ro,no_subtree_check,fsid=11)" >> /etc/exports
exportfs -a
systemctl restart nfs-server
systemctl enable nfs-server


# Optional steps

## Enable ssh control via resource manager
echo "account required pam_slurm.so" >> $CHROOT/etc/pam.d/sshd
## Enable forwarding of system logs
echo 'module(load="imudp")' >> /etc/rsyslog.d/ohpc.conf
echo 'input(type="imudp" port="514")' >> /etc/rsyslog.d/ohpc.conf
systemctl restart rsyslog
echo "*.* action(type=\"omfwd\" Target=\"${sms_ip}\" Port=\"514\" " \
"Protocol=\"udp\")">> $CHROOT/etc/rsyslog.conf
perl -pi -e "s/^\*\.info/\\#\*\.info/" $CHROOT/etc/rsyslog.conf
perl -pi -e "s/^authpriv/\\#authpriv/" $CHROOT/etc/rsyslog.conf
perl -pi -e "s/^mail/\\#mail/" $CHROOT/etc/rsyslog.conf
perl -pi -e "s/^cron/\\#cron/" $CHROOT/etc/rsyslog.conf
perl -pi -e "s/^uucp/\\#uucp/" $CHROOT/etc/rsyslog.conf
## Add ClusterShell
sudo dnf -y install clustershell
cd /etc/clustershell/groups.d
mv local.cfg local.cfg.orig
echo "adm: ${sms_name}" > local.cfg
echo "compute: ${compute_prefix}[1-${num_computes}]" >> local.cfg
echo "all: @adm,@compute" >> local.cfg
## Add genders
sudo dnf -y install genders-ohpc
echo -e "${sms_name}\tsms" > /etc/genders
for ((i=0; i<$num_computes; i++)) ; do
    echo -e "${c_name[$i]}\tcompute,bmc=${c_bmc[$i]}"
done >> /etc/genders
## Add Magpie
sudo dnf -y install magpie-ohpc
## Add ConMan
sudo dnf -y install conman-ohpc
for ((i=0; i<$num_computes; i++)) ; do
    echo -n 'CONSOLE name="'${c_name[$i]}'" dev="ipmi:'${c_bmc[$i]}'" '
    echo 'ipmiopts="'U:${bmc_username},P:${IPMI_PASSWORD:-undefined},W:solpayloadsize'"'
done >> /etc/conman.conf
systemctl enable conman
systemctl start conman
## Add NHC
sudo dnf -y install nhc-ohpc
sudo dnf -y --installroot=$CHROOT install nhc-ohpc
echo "HealthCheckProgram=/usr/sbin/nhc" >> /etc/slurm/slurm.conf
echo "HealthCheckInterval=300" >> /etc/slurm/slurm.conf
## Import files
wwsh file import /etc/passwd
wwsh file import /etc/group
wwsh file import /etc/shadow
wwsh file import /etc/munge/munge.key

# Finalize provisioning configuration
export WW_CONF=/etc/warewulf/bootstrap.conf
echo "drivers += updates/kernel/" >> $WW_CONF
wwbootstrap `uname -r`
wwvnfs --chroot $CHROOT


# HARD part - nodes have to be connected, and ready for PXE boot
## This is not on the tutorial, but only way I found to see them with tcpdump
sudo ip addr add 10.0.8.1/24 dev enp0s8
sudo ip link set enp0s8 up

sudo tcpdump -i enp0s8 port 67 or port 68       # see if they make requests when starting headless
#wwnodescan --netdev=enp0s8 --ipaddr=10.0.8.100 --netmask=255.255.255.0 --vnfs=rocky9.3 --bootstrap=$(uname -r) --listen=enp0s8 compute1    # this should work, if not, try disconnecting the network, and connecting it again




echo "GATEWAYDEV=${eth_provision}" > /tmp/network.$$
wwsh -y file import /tmp/network.$$ --name network
wwsh -y file set network --path /etc/sysconfig/network --mode=0644 --uid=0
# Add nodes to Warewulf data store
for ((i=0; i<$num_computes; i++)) ; do
    wwsh -y node new ${c_name[i]} --ipaddr=${c_ip[i]} --hwaddr=${c_mac[i]} -D ${eth_provision}
done
#Additional step required if desiring to use predictable network interface naming schemes
export kargs="net.ifnames=1 biosdevname=1"
wwsh provision set --postnetdown=1 "${compute_regex}"
wwsh -y provision set "${compute_regex}" --vnfs=rocky9.3 --bootstrap=`uname -r` \
--files=dynamic_hosts,passwd,group,shadow,munge.key,network
#wwnodescan --netdev=${eth_provision} --ipaddr=${c_ip[0]} --netmask=${internal_netmask} \
#--vnfs=rocky9.3 --bootstrap=`uname -r` --listen=${sms_eth_internal} ${c_name[0]}-${c_name[3]}
systemctl restart dhcpd
wwsh pxe update
for ((i=0; i<${num_computes}; i++)) ; do
    ipmitool -E -I lanplus -H ${c_bmc[$i]} -U ${bmc_username} -P ${bmc_password} chassis power reset
done


