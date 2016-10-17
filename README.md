# Hark! Deploy an HA cluster in Virtual Machines

Hark! is a tool to deploy various types of HA clusters without having
to create a base image. It uses libvirt and autoyast to automate the
creation and base configuration of virtual machines.

## Usage

```
usage: hark [-h] [-q] [-n] [-x] [-d] [-s SCENARIO]
            {download,config,status,up,halt,destroy,bootstrap,test} ...

Hark! A tool for setting up a test cluster for SLE HA. Configure your
scenarios using the hark.ini and scenario files. Run 'up' to prepare the host
and create virtual machines, run 'status' to see the state of the cluster, and
once installation completes, run 'bootstrap' to configure the cluster.

positional arguments:
  {download,config,status,up,halt,destroy,bootstrap,test}
    download            List available variants and download ISO files for
                        variants
    config              Display resolved configuration values
    status              Display status of configuration
    up                  Configure the host and bring virtual machines up
    halt                Tell running VMs to halt
    destroy             Halt and destroy any created VMs
    bootstrap           Bootstrap initial cluster
    test                Run cluster test

optional arguments:
  -h, --help            show this help message and exit
  -q, --quiet           Minimal output
  -n, --non-interactive
                        Assume yes to all prompts
  -x, --debug           Halt in debugger on error
  -d, --download        Download missing ISO files automatically
  -s SCENARIO, --scenario SCENARIO
                        Cluster scenario
```

## History

Originally this was a set of scripts that did mostly the same thing
but only for a 4 node cluster. Description of original scripts below:

### Easily Deploy an HA cluster in Virtual Machines

The goal was to easily and quickly deploy an HA cluster in Virtual
Machine to be able to test latest release and test some scenarios.

Videos: Presentation and a demo at Youtube:
* https://www.youtube.com/watch?v=y0herkr6x-A
* https://www.youtube.com/watch?v=vmUpaabYV-o
* https://www.youtube.com/watch?v=k77sa9y6Lwk

This scripts will configure:
* an host (by default KVM)
* 4 HA nodes ready for HA scenario

All configurations files on the host are dedicated for this cluster, which means
this should not interact or destroy any other configuration (pool, net, etc...)

Please report any bugs or improvments to:
https://github.com/aginies/Deploy_HA_SLE_cluster.git

## Features

* Automatically download the latest ISO
* Configure different scenarios with minimal changes needed
* Pre-install SSH keys for easy access after configuration
* Parallel background installation of VMs

## Configuration

Create different configuration scenarios using the `scenarios/*.ini`
files. See the existing scenarios for details on what can be
configured.

* Per-VM configuration (VCPUs, RAM, etc.)
* Package list to install
* Addons and base image

Basic configuration (username, password, etc.) is done in the
`hark.ini` file. See the `hark.ini.example` file for an example
configuration. The ISO download URL, username and local storage paths
will need to be modified.

* *WARNING* All guest installation will be done at the same time.

## Install / HOWTO

* Clone this repository
* Copy `hark.ini.example` to `hark.ini`
* Adjust settings to your liking
* Verify the configuration using `./hark config`
* Configure the host and create VMs: `./hark up`
* Bootstrap the cluster (optional): `./hark bootstrap`
* See status using `./hark status`
* Your HA cluster is now able to run some HA tests

*Note*: Executed actions and commands are logged to `./hark.log`.

*Note*: Background installation processes log to `./screenlog.0`.

## Scenario configuration files

Most variables should be self-explanatory. Define virtual machine
instances with a section per virtual machine, with a section title as
`[vm:<name>]`.

Configure Addons to download and install using the `[addon:<name>]`
syntax. The base addon is used as the installation image.

## Scripts

### HA_testsuite_init_cluster.sh
Finish the nodes installation and run some tests.
The ha-cluster-init script will be run on node HA1.

*NOTE* This script still needs some work to handle the various
 scenarios configurable by `hark`.

*NOTE* Use the `[force]` option to bypass the HA cluster check.

## AutoYast templates

The AutoYast files used for auto-installation are based on the
templates found in `templates/`. These may need to be modified for
different versions of SLE or openSUSE.

## Example configuration (hark.ini)

```
[iso]
path=/mnt/ISO/
url=http://repo.example.com/iso/

[host]
hypervisor=kvm

[network]
name=HAnet
range=192.168.12
uuid=851e50f1-db72-475a-895f-28304baf8e8c
hostmac=52:54:00:89:a0:b9
interface=virbr1
mac=52:54:00:c7:92:

[storage]
path=/var/lib/libvirt/images
vmpool=hapool
sharedpool=hashared
shareddisk={path}/{sharedpool}/{sharedpool}.img
shareddevice=/dev/vdb
sharedsize=1G

[user]
keymap=us
sshkey=id_rsa_ha
name=krig
password=linux

[scenario]
default=2node
```

## Example scenario (scenarios/3node.ini)

```
[common]
distro=SLE12SP1
vcpu=2
ram=2048
imagesize=8G
keymap=english-us
timezone=Europe/Stockholm
packages=openssh vim autoyast2 ntp patterns-ha-ha_sles haproxy apache2 mariadb mariadb-tools bridge-utils git-core perl-Error
autoyastdisk={config.storage.path}/threenode.raw

[addon:sle_ha]
iso={config.iso.url}/SLE-12-SP1-HA-DVD-x86_64-*-Media1.iso

[addon:base]
iso={config.iso.url}/SLE-12-SP1-Server-DVD-x86_64-*-Media1.iso

[vm:ha31]
address={config.network.range}.131
fqdn={name}.testing.com
mac={config.network.mac}da

[vm:ha32]
address={config.network.range}.132
fqdn={name}.testing.com
mac={config.network.mac}db

[vm:ha33]
address={config.network.range}.133
fqdn={name}.testing.com
mac={config.network.mac}db
```

# Example installation run

```
host$ ./hark --scenario geo up
  Install virtualization stack for openSUSE...done
  Prepare /etc/hosts
  Prepare virtual network (/etc/libvirt/qemu/networks/HAnet.xml)......done
  Prepare and create shard pool and volume.......done
  Prepare the Autoyast image for VM guest installation
  Cleanup VM
  Create pool hatwonode
  Check disks before install
  Install VM hageo11
  Install VM hageo12
  Install VM hageo21
  Install VM hageo22
  Install VM haarbitrator
# Networks:
   HAnet                active     yes           yes

# Pools:
   hashared             active     yes
   hatwonode            active     yes

# Volumes:
   SLE12SP2haarbitrator.qcow2 /home/krig/vms/hatwonode/SLE12SP2haarbitrator.qcow2
   SLE12SP2hageo11.qcow2 /home/krig/vms/hatwonode/SLE12SP2hageo11.qcow2
   SLE12SP2hageo12.qcow2 /home/krig/vms/hatwonode/SLE12SP2hageo12.qcow2
   SLE12SP2hageo21.qcow2 /home/krig/vms/hatwonode/SLE12SP2hageo21.qcow2
   SLE12SP2hageo22.qcow2 /home/krig/vms/hatwonode/SLE12SP2hageo22.qcow2
   hashared.img         /home/krig/vms/hashared/hashared.img

# Virtual machines:

# IP Addresses:

# Installations in progress:
   22739.install_HA_VM_guest_SLE12SP2haarbitrator	(Detached)
   22723.install_HA_VM_guest_SLE12SP2hageo22	(Detached)
   22706.install_HA_VM_guest_SLE12SP2hageo21	(Detached)
   22687.install_HA_VM_guest_SLE12SP2hageo12	(Detached)
   22673.install_HA_VM_guest_SLE12SP2hageo11	(Detached)
```

# Example post-installation status

```
host$ ./hark --scenario geo status
# Networks:
   HAnet                active     yes           yes

# Pools:
   hashared             active     yes
   hatwonode            active     yes

# Volumes:
   SLE12SP2haarbitrator.qcow2 /home/krig/vms/hatwonode/SLE12SP2haarbitrator.qcow2
   SLE12SP2hageo11.qcow2 /home/krig/vms/hatwonode/SLE12SP2hageo11.qcow2
   SLE12SP2hageo12.qcow2 /home/krig/vms/hatwonode/SLE12SP2hageo12.qcow2
   SLE12SP2hageo21.qcow2 /home/krig/vms/hatwonode/SLE12SP2hageo21.qcow2
   SLE12SP2hageo22.qcow2 /home/krig/vms/hatwonode/SLE12SP2hageo22.qcow2
   hashared.img         /home/krig/vms/hashared/hashared.img

# Virtual machines:
   6     SLE12SP2haarbitrator           running
   7     SLE12SP2hageo12                running
   8     SLE12SP2hageo11                running
   10    SLE12SP2hageo22                running
   11    SLE12SP2hageo21                running

# IP Addresses:
   2016-10-17 11:37:11  52:54:00:c7:92:ea  ipv4      192.168.12.111/24         hageo11         01:52:54:00:c7:92:ea
   2016-10-17 11:37:06  52:54:00:c7:92:eb  ipv4      192.168.12.112/24         hageo12         01:52:54:00:c7:92:eb
   2016-10-17 11:41:19  52:54:00:c7:92:ec  ipv4      192.168.12.113/24         hageo21         01:52:54:00:c7:92:ec
   2016-10-17 11:37:14  52:54:00:c7:92:ed  ipv4      192.168.12.114/24         hageo22         01:52:54:00:c7:92:ed
   2016-10-17 11:36:56  52:54:00:c7:92:ee  ipv4      192.168.12.115/24         haarbitrator    01:52:54:00:c7:92:ee

# Installations in progress:
```
