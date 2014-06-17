#!/bin/bash

usage() {
cat <<EOF
usage: $0 options

OPTIONS:
-h                  Show this message
-c 					Create test environment
-d 					Delete test environment
EOF
}
export -f usage


# Grab the openstack credentials
source ~/openrc

create() {
	if [ ! -z "`glance image-list | grep trusty`"] ;then
		glance image-create --name=trusty --disk-format=qcow2 --container-format=bare --is-public=true \
		--location=https://cloud-images.ubuntu.com/trusty/current/trusty-server-cloudimg-amd64-disk1.img \
	fi

 
# Create user data if it doesn't exist
if [ ! -d ~/user.data ]; then
cat > ~/user.data <<EOF
#!/bin/bash

apt-get install vlan -y
echo 8021q >> /etc/modules
modprobe 8021q
vconfig add eth0 144
ip_host=`ip addr show eth0 | awk '/ inet / {print $2}' | cut -d/ -f1 | cut -d. -f4`
ifconfig eth0.144 10.0.144.\$ip_host netmask 255.255.255.0 mtu 8950 up
EOF
fi

if [ ! -z "`nova keypair-list | grep root`"] ;then
	ssh-keygen -t rsa -f ~/.ssh/id_rsa -N ''
	nova keypair-add --pub-key ~/.ssh/id_rsa.pub root
fi

neutron net-create --tenant-id `keystone tenant-list | awk '/ openstack /  {print $2}'` \
  sharednet1 --shared --provider:network_type flat --provider:physical_network physnet1
neutron subnet-create --ip-version 4 --tenant-id `keystone tenant-list | awk '/ openstack / {print $2}'` \
 sharednet1 10.0.149.0/24 --allocation-pool start=10.0.149.100,end=10.0.149.200 --dns_nameservers \
 list=true 10.0.100.15

neutron net-create --tenant-id `keystone tenant-list | awk '/ openstack /  {print $2}'` tenantnet1
neutron subnet-create --ip-version 4 --tenant-id `keystone tenant-list | awk '/ openstack / {print $2}'` \
 tenantnet1 192.168.0.0/24 --allocation-pool start=192.168.0.100,end=192.168.0.200 --dns_nameservers \
 list=true 10.0.100.15

nova boot --flavor 2 --image trusty --nic net-id=`neutron net-list | awk '/ sharednet1 /  {print $2}'` \
  --nic net-id=`neutron net-list | awk '/ tenantnet1 / {print $2}'` --key-name root \
  --user-data ~/user.data vxa

nova boot --flavor 2 --image trusty --nic net-id=`neutron net-list | awk '/ sharednet1 / {print $2}'` \
  --nic net-id=`neutron net-list | awk '/ tenantnet1 / {print $2}'` --key-name root \
  --user-data ~/user.data vxb
}
export -f create

delete() {
nova delete vxa
if [ $? ] ; then echo Deleted vxa; fi
nova delete vxb
if [ $? ] ; then echo Deleted vxb; fi

neutron net-delete sharednet1

neutron net-delete tenantnet1

glance image-delete trusty
if [ $? ] ; then echo Deleted trusty; fi
}
export -f delete

# parse CLI options
while getopts "hcd" OPTION
do
  case $OPTION in
    h)
      usage
      exit 1
      ;;
    c)
	  create
	  exit 0
	  ;;
	d)
	  delete
	  exit 0
	  ;;
  esac
done


