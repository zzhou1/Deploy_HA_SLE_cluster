#!/bin/sh
#########################################################
#
#
#########################################################
## HOST CONFIGURATION
#########################################################

# ie: ISO as source of RPM:
#zypper addrepo "iso:/?iso=SLE-12-SP2-Server-DVD-x86_64-Buildxxxx-Media1.iso&url=nfs://10.0.1.99/volume1/install/ISO/SP2devel/" ISOSLE
#zypper addrepo "iso:/?iso=SLE-12-SP2-HA-DVD-x86_64-Buildxxxx-Media1.iso&url=nfs://10.0.1.99/volume1/install/ISO/SP2devel/" ISOHA

if [ -f `pwd`/functions ] ; then
    . `pwd`/functions
else
    echo "! need functions in current path; Exiting"; exit 1
fi
check_load_config_file ha_kvm_host.conf


# Install all needed Hypervisors tools
install_virtualization_stack() {
    echo "############ START install_virtualization_stack #############"
    echo "- patterns-sles-${HYPERVISOR}_server patterns-sles-${HYPERVISOR}_tools and restart libvirtd"
    zypper in -y patterns-sles-${HYPERVISOR}_server
    zypper in -y patterns-sles-${HYPERVISOR}_tools
    echo "- Restart libvirtd"
    if ! systemctl restart libvirtd; then echo $F " ... failed"; exit 1; fi
}

# ssh root key on host
# should be without password to speed up command on HA NODE
ssh_root_key() {
    echo "############ START ssh_root_key #############"
    echo "- Generate ~/.ssh/${IDRSAHA} without password"
    ssh-keygen -t rsa -f ~/.ssh/${IDRSAHA} -N ""
    echo "- Create /root/.ssh/config for HA nodes access"
    CONFIGSSH="/root/.ssh/config"
    grep ${DISTRO}${NODENAME}2 $CONFIGSSH
    if [ "$?" -ne "0" ]; then
	cat >> $CONFIGSSH<<EOF
host ${NODENAME}1 ${NODENAME}2 ${NODENAME}3 ${DISTRO}${NODENAME}1 ${DISTRO}${NODENAME}2 ${DISTRO}${NODENAME}3
IdentityFile /root/.ssh/${IDRSAHA}
EOF
	else
	echo "- seems $CONFIGSSH already contains needed modification"
	echo "- Should be something like:
host ${NODENAME}1 ${NODENAME}2 ${NODENAME}3 ${DISTRO}${NODENAME}1 ${DISTRO}${NODENAME}2 ${DISTRO}${NODENAME}3
IdentityFile /root/.ssh/${IDRSAHA}
"
    fi
}

# Connect as root in VMguest without Password, copy root host key
# pssh will be used
# Command from Host
prepare_remote_pssh() {
    echo "############ START prepare_remote_pssh #############"
    echo "- Install pssh and create ${PSSHCONF}"
    zypper in -y pssh
    cat > ${PSSHCONF}<<EOF
${NODENAME}1
${NODENAME}2
${NODENAME}3
EOF
}

# ADD node to /etc/hosts (hosts)
prepare_etc_hosts() {
    echo "############ START prepare_etc_hosts #############"
    grep ${NODENAME}1.${NODEDOMAIN} /etc/hosts
    if [ $? == "1" ]; then
        echo "- Prepare /etc/hosts (adding HA nodes)"
    cat >> /etc/hosts <<EOF
${NETWORK}.101  ${NODENAME}1.${NODEDOMAIN} ${NODENAME}1 ${DISTRO}${NODENAME}1
${NETWORK}.102  ${NODENAME}2.${NODEDOMAIN} ${NODENAME}2 ${DISTRO}${NODENAME}2
${NETWORK}.103  ${NODENAME}3.${NODEDOMAIN} ${NODENAME}3 ${DISTRO}${NODENAME}3
EOF
    else
        echo "- /etc/hosts already ok"
    fi
}

# Define HAnet private HA network (NAT)
# NETWORK will be ${NETWORK}.0/24 gw/dns ${NETWORK}.1
prepare_virtual_HAnetwork() {
    if [ ! $1 == "" ]; then NETWORK=$1; fi
    echo "############ START prepare_virtual_HAnetwork #############"
    echo "- Prepare virtual HAnetwork (/etc/libvirt/qemu/networks/${NETWORKNAME}.xml)"
    cat > /etc/libvirt/qemu/networks/${NETWORKNAME}.xml << EOF
<network>
  <name>${NETWORKNAME}</name>
  <uuid>${UUID}</uuid>
  <forward mode='nat'/>
  <bridge name='${BRIDGE}' stp='on' delay='0'/>
  <mac address='${NETMACHOST}'/>
  <domain name='${NETWORKNAME}'/>
  <ip address='${NETWORK}.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='${NETWORK}.128' end='${NETWORK}.254'/>
      <host mac="${MACA}" name="${DISTRO}${NODENAME}1.${NODEDOMAIN}" ip="${NETWORK}.101" />
      <host mac="${MACB}" name="${DISTRO}${NODENAME}2.${NODEDOMAIN}" ip="${NETWORK}.102" />
      <host mac="${MACC}" name="${DISTRO}${NODENAME}3.${NODEDOMAIN}" ip="${NETWORK}.103" />
    </dhcp>
  </ip>
</network>
EOF
    virsh net-autostart ${NETWORKNAME}|| ( echo $F "! Fatal error: net-autostart ${NETWORKNAME}"; exit 1 )

    echo "- Start ${NETWORKNAME}"
    virsh net-list | grep ${NETWORKNAME}
    if [ x$? = x0 ]; then
       virsh net-destroy ${NETWORKNAME}|| ( echo $F "! Fatal error: net-destory ${NETWORKNAME}"; exit 1 )
    fi
    systemctl restart libvirtd
}

# Create an SBD pool on the host 
prepare_SBD_pool() {
    echo "############ START prepare_SBD_pool"
# Create a pool SBD
    virsh pool-list --all | grep ${SBDNAME} > /dev/null
    if [ $? == "0" ]; then
    	echo "- Destroy current pool ${SBDNAME}"
    	virsh pool-destroy ${SBDNAME}
    	echo "- Undefine current pool ${SBDNAME}"
    	virsh pool-undefine ${SBDNAME}
        rm -vf ${SBDDISK}
    else
        echo "- ${SBDNAME} pool is not present"
    fi
    echo "- Define pool ${SBDNAME}"
    mkdir -p ${STORAGEP}/${SBDNAME}
    virsh pool-define-as --name ${SBDNAME} --type dir --target ${STORAGEP}/${SBDNAME}
    echo "- Start and Autostart the pool"
    virsh pool-start ${SBDNAME}
    virsh pool-autostart ${SBDNAME}

# Create the VOLUME SBD.img
    echo "- Create ${SBDNAME}.img"
    virsh vol-create-as --pool ${SBDNAME} --name ${SBDNAME}.img --format raw --allocation 10M --capacity 10M
}

# Create a RAW file which contains auto install file for deployment
prepare_auto_deploy_image() {
    echo "############ START prepare_auto_deploy_image #############"
    echo "- Prepare the autoyast image for VM guest installation (havm_xml.raw)"
    WDIR=`pwd`
    #WDIR2="/tmp/tmp_ha"
    #WDIRMOUNT="/mnt/tmp_ha"
    WDIR2=`mktemp -d /tmp/ha-autoyast-img-XXXXXX`
    WDIRMOUNT="/mnt/`basename $WDIR2`"
    mkdir -p ${WDIRMOUNT}
    mkdir -p ${STORAGEP}
    cd ${STORAGEP}
    cp -avf ${WDIR}/havm*.xml ${WDIR2}
    sleep 1
    perl -pi -e "s/NETWORK/${NETWORK}/g" ${WDIR2}/havm.xml
    perl -pi -e "s/NODEDOMAIN/${NODEDOMAIN}/g" ${WDIR2}/havm.xml
    perl -pi -e "s/NODENAME/${NODENAME}/g" ${WDIR2}/havm.xml
    perl -pi -e "s/FHN/${DISTRO}${NODENAME}/g" ${WDIR2}/havm.xml
    perl -pi -e "s/NETWORK/${NETWORK}/g" ${WDIR2}/havm_mini.xml
    perl -pi -e "s/NODEDOMAIN/${NODEDOMAIN}/g" ${WDIR2}/havm_mini.xml
    perl -pi -e "s/NODENAME/${NODENAME}/g" ${WDIR2}/havm_mini.xml
    perl -pi -e "s/FHN/${DISTRO}${NODENAME}/g" ${WDIR2}/havm_mini.xml
    qemu-img create havm_xml.raw -f raw 2M
    mkfs.ext3 havm_xml.raw
    mount havm_xml.raw ${WDIRMOUNT}
    cp -v ${WDIR2}/havm.xml ${WDIRMOUNT}
    cp -v ${WDIR2}/havm_mini.xml ${WDIRMOUNT}
    umount ${WDIRMOUNT}
    rm -rf ${WDIRMOUNT} ${WDIR2}
}

check_host_config() {
    echo "############ START check_host_config #############"
    echo "- Show net-list"
    virsh net-list
    echo "- Display pool available"
    virsh pool-list
#    echo "- List volume available in ${SBDNAME}"
#    virsh vol-list ${SBDNAME}
}

###########################
###########################
#### MAIN
###########################
###########################

echo "############ PREPARE HOST #############"
echo "  !! WARNING !! "
echo "  !! WARNING !! "
echo 
echo "  This will remove any previous Host configuration for HA VM guests and testing"
echo
echo " press [ENTER] twice OR Ctrl+C to abort"
read
read

ssh_root_key
install_virtualization_stack
#prepare_remote_pssh
#prepare_etc_hosts
prepare_virtual_HAnetwork 
#prepare_SBD_pool
prepare_auto_deploy_image
check_host_config
