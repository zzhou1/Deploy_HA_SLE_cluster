#!/bin/sh
#########################################################
#
#
#########################################################
## INSTALL HA Guest (and checks)
#########################################################

if [ -f `pwd`/functions ] ; then
    . `pwd`/functions
else
    echo "! need functions in current path; Exiting"; exit 1
fi
check_load_config_file ha_kvm_host.conf

# global VAR
LIBVIRTPOOL="nodes_images"
DISKHAVM="${STORAGEP}/havm_xml.raw"
EXTRAARGS="autoyast=device://vdb/havm.xml"


detect_installation_media() {
    if [ $# -lt 1 ]; then  echo "! 1 arg needed (CMD);Exiting"; exit 1; fi
   
    if [ ! -f $1 ]; then
        echo $W "! $1 can not be found, continue to check if it exists in CDROM devices."; 

	TEMP="`basename "$1"|sed 's/_.*//'`"
	[ "$TEMP" == "" ] && (echo $F "'$1' not exist. Exiting!"; exit 1;)

	TEMP2=`blkid|grep "$TEMP"` 

	if [ ! $? ]; then 
		echo $F "! ${1} can not be found in CDROM devices neither. Fix this in ${CONF}. Exiting!" ; 
		exit 1; 
	fi

	echo $TEMP2|awk -F: '{print $1}'
    fi
}

HACDROM="`detect_installation_media $HACDROM`"
SLECDROM="`detect_installation_media $SLECDROM`"

# clean up previous VM
cleanup_vm() {
    HANAME="${DISTRO}${NODENAME}"
    echo "############ START cleanup_vm #############"
    echo "  !! WARNING !! "
    echo "  !! WARNING !! "
    if [ -d ${STORAGEP}/${LIBVIRTPOOL} ]; then
        echo "- This will remove previous HA VM guest image (in ${STORAGEP}/${LIBVIRTPOOL} dir)"
        cd ${STORAGEP}/${LIBVIRTPOOL}
        ls -1 ${HANAME}*.qcow2
    fi
    echo
    echo " press [ENTER] twice OR Ctrl+C to abort"
    read
    read
    #for nb in `seq 1 3`
    #do 
	#NAME="${HANAME}${nb}"
	#virsh list --all | grep ${NAME} > /dev/null
    VMs_N=`virsh list --all|grep ${HANAME}|awk '{print $2}'`
    for NAME in ${VMs_N}
    do
	if [ $? == "0" ]; then
    	    echo "- Destroy current VM: ${NAME}"
    	    virsh destroy ${NAME}
    	    echo "- Undefine current VM: ${NAME}"
    	    virsh undefine ${NAME}
	else
            echo "- ${NAME} is not present"
	fi
	echo "- Remove previous image file for VM ${NAME} (${NAME}.qcow2)"
	rm -rvf ${STORAGEP}/${LIBVIRTPOOL}/${NAME}.qcow2
    done
}

# Install VM  
install_vm() {
    echo "############ START install_vm #############"
    # pool refresh to avoid error
    virsh pool-refresh ${LIBVIRTPOOL}
    echo "- Create new VM guest image file: ${NAME}.qcow2 ${IMAGESIZE}"
    virsh vol-create-as --pool ${LIBVIRTPOOL} --name ${NAME}.qcow2 --capacity ${IMAGESIZE} --allocation ${IMAGESIZE} --format qcow2
    virsh pool-refresh ${LIBVIRTPOOL}
    if [ ! -f ${VMDISK} ]; then echo "- ${VMDISK} NOT present"; exit 1; fi
    echo "- Start VM guest installation in a screen"

    check_cmd_installation screen
    screen -d -m -S "install_HA_VM_guest_${NAME}" virt-install --name ${NAME} \
	   --ram ${RAM} \
	   --vcpus ${VCPU} \
	   --virt-type kvm \
	   --os-variant sles12sp3 \
	   --graphics vnc,keymap=${KEYMAP} \
	   --network network=${NETWORKNAME},mac=${MAC} \
	   --disk path=${VMDISK},format=qcow2,bus=virtio \
	   --disk path=${DISKHAVM},bus=virtio \
	   --disk path=${HACDROM},device=cdrom \
	   --disk path=${SLECDROM},device=cdrom \
	   --location ${SLECDROM} \
	   --boot hd,cdrom \
	   --extra-args ${EXTRAARGS} \
	   --watchdog i6300esb,action=poweroff \
	   --console pty,target_type=virtio \
	   --check all=off
}

check_before_install() {
    echo "############ START check_before_install #############"
    if [ ! -f ${DISKHAVM} ]; then 
        echo "- ${DISKHAVM} NOT present, needed for auto installation"; exit 1
    else
        echo "- ${DISKHAVM} is present"
    fi
    if [ ! -f ${SBDDISK} ]; then 
        echo "- ${SBDDISK} NOT present, needed for STONITH (SBD devices)"; exit 1
    else
        echo "- ${SBDDISK} is present"
    fi
}

copy_ssh_key() {
    echo "- Don't forget to copy the root host SSH key to VM guest
ssh-copy-id -f -i /root/.ssh/${IDRSAHA}.pub -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${NODENAME}1
ssh-copy-id -f -i /root/.ssh/${IDRSAHA}.pub -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${NODENAME}2
ssh-copy-id -f -i /root/.ssh/${IDRSAHA}.pub -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${NODENAME}3"
echo 
echo "- Clean up your /root/.ssh/known_hosts from previous config (dirty way below)
rm -vf /root/.ssh/known_hosts"
}

##########################
##########################
### MAIN
##########################
##########################

# CLEAN everything
cleanup_vm

# create the pool
create_pool ${LIBVIRTPOOL}

# verify everything is available
#check_before_install


# Reset shell timer to measure Installation time.
SECONDS=0

# Install HOST VM
NAME="${DISTRO}${NODENAME}1"
MAC="${MACA}"
VMDISK="${STORAGEP}/${LIBVIRTPOOL}/${NAME}.qcow2"
install_vm

# Use a minimal installation without X for HA2 and HA3 etc...
# Install HA2 VM
NAME="${DISTRO}${NODENAME}2"
MAC="${MACB}"
VMDISK="${STORAGEP}/${LIBVIRTPOOL}/${NAME}.qcow2"
install_vm

# Install HA3 VM
#NAME="${DISTRO}${NODENAME}3"
#MAC="${MACC}"
#VMDISK="${STORAGEP}/${LIBVIRTPOOL}/${NAME}.qcow2"
#sleep 5
#install_vm

# Check VM
sleep 5
virsh list --all

# Get IP address
virsh net-dhcp-leases ${NETWORKNAME}

# List installation in progress
screen -list

#copy_ssh_key


# Report the rough installation duration
# Wait for the last VM
IP_ADDR_LAST_VM=`grep $MAC /etc/libvirt/qemu/networks/${NETWORKNAME}.xml|sed -n 's/.*ip="\(.*\)".*/\1/p'`
TIMEOUT_COUNT="600"
for nb in `seq 1 $TIMEOUT_COUNT`
do 
    ping -q -W 1 -c 1 ${IP_ADDR_LAST_VM} > /dev/null && break
done  
if [ "$nb" == "$TIMEOUT_COUNT" ]; then
    echo $W "Warning: installation cost more than $nb seconds!"; 
else
    echo "Installation is done in about $SECONDS seconds. Enjoy your login..."
    echo "ssh root@$IP_ADDR_LAST_VM"
fi 

