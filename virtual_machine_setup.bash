# Verify virtualization is enabled - must show either vmx or svm
egrep -c '(vmx|svm)' /proc/cpuinfo

# 2. Install required software for virtualization - libvirt-bin is no longer available in Ubuntu 20.04
sudo apt-get install qemu-kvm libvirt-daemon-system libvirt-clients

# 3. Configure Bridged Networking
sudo apt-get install bridge-utils
sudo brctl addbr br0
systemctl status network-manager.service
echo "manual" | sudo tee /etc/init/network-manager.override

# 4. 


