#!/bin/bash
# grab the puppet_openstack_builder code
# and update it if it doesn't have the right
# elements already defined for VLAN/VXLan/LB
# 
# Also, create a new scenario, and role mapping
# for this enviornment
exec > >(tee /var/log/lb_vxlan_build_setup.log)
exec 2>&1
set -o errexit

usage() {
cat <<EOF
usage: $0 options

OPTIONS:
-h                  Show this message
-p {proxy_address}  http proxy i.e. -p http://username:password@host:port/
-v {vlan}           single interface vlan to enable
-m                  set 8950 MTU
-r                  run install.sh for all_in_one/lb_vxlan use case
-i {ipaddress}      vlan interface ip address
-n {netmask}        vlan interfac netmask
-g {gateway}        vlan interface gateway
-d {dns}            vlan interface dns ip
-t {ntp}            ntp server address
-D {default_int}    default interface (usually eth0)
-E {external_int}   external interface (usually eth1)
-I {interfaces}     interfaces : separated (usually eth0:eth1:eth2:eth3)
-M {mtu_interfaces} interfaces with MTUs : separated (eth3:9000:eth4:9000)
EOF
}
export -f usage

if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root or with sudo"
    usage
    exit 1
fi


# wrapper all commands with sudo in case this is not run as root
# also map in a proxy in case it was passed as a command line argument
function run_cmd () {
  if [ -z "$PROXY" ]; then
    sudo $*
  else
    sudo env http_proxy=$PROXY https_proxy=$PROXY $*
  fi
}
export -f run_cmd

# Define some useful APT parameters to make sure you get the latest versions of code

APT_CONFIG="-o Acquire::http::No-Cache=True -o Acquire::BrokenProxy=true -o Acquire::Retries=3"

# check if the environment is set up for http and https proxies
if [ -n "$http_proxy" ]; then
  if [ -z "$https_proxy" ]; then
    echo "Please set https_proxy env variable."
    exit 1
  fi
  PROXY=$http_proxy
fi

function valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

export valid_ip

# parse CLI options
while getopts "hmrp:v:i:n:g:d:t:D:E:I:M:" OPTION
do
  case $OPTION in
    h)
      usage
      exit 1
      ;;
    p)
      PROXY=$OPTARG
      export http_proxy=$PROXY
      export https_proxy=$PROXY
      ;;
    v)
      VLAN=$OPTARG
      export vlan=$VLAN
      ;;
    m)
      export MTU=9000
      ;;
    r)
      export run_all_in_one=true
      ;;
    i)
      export ip_address=$OPTARG
      ;;
    n)
      export ip_netmask=$OPTARG
      ;;
    g)
      export ip_gateway=$OPTARG
      ;;
    d)
      export dns_address=$OPTARG
      ;;
    t)
      export ntp_address=$OPTARG
      ;;
    D)
      export default_interface=$OPTARG
      ;;
    E)
      export external_interface=$OPTARG
      ;;
    I)
      export interfaces=$OPTARG
      ;;
    M)
      export mtus=$OPTARG
  esac
done

if [ $# -eq 0 ] ;then
  usage
  exit 1
fi

# Make sure the apt repository list is up to date
echo -e "\n\nUpdate apt repository...\n\n"
if ! run_cmd apt-get $APT_CONFIG update; then
  echo "Can't update apt repository"
  exit 1
fi

# Install prerequisite packages
echo "Installing prerequisite apps: git, vlan, vim..."
if ! run_cmd apt-get $APT_CONFIG install -qym git vlan vim; then
  echo "Can't install prerequisites!..."
  exit 1
fi

echo "configure vhost_net module for better VM network performance"
echo 'vhost_net' >> /etc/modules
modprobe vhost_net


echo "Enable 8021q module for VLAN config"
if [ -z "`grep 8021q /etc/modules`" ] ;then 
  echo 8021q >> /etc/modules
  modprobe 8021q
fi

if [ ! -z "${VLAN}" ] ;then
  while true; do
    if [ -z "$ip_address" ] ;then
      while true; do
        read -ep "Enter the VLAN:${VLAN} IPv4 Address: " ip_address
        if ! valid_ip $ip_address ; then
          echo "That's not an IP address"
        else
          break
        fi
      done
    fi

    if [ -z "$ip_netmask" ] ;then
      while true; do
        read -ep "Enter the VLAN:${VLAN} Netmask: " ip_netmask
        if ! valid_ip $ip_netmask ; then
          echo "That's not a valid IPv4 Netmask"
        else
          break
        fi
      done
    fi

    if [ -z "$ip_gateway" ] ;then
      while true; do
        read -ep "Enter the VLAN:${VLAN} IPv4 Gateway: " ip_gateway
        if ! valid_ip $ip_gateway ; then
          echo "That's not a valid IPv4 address"
        else
          break
        fi
      done
    fi

    if [ -z "$dns_address" ] ;then
      while true; do
        read -ep "Enter the initial VLAN:${VLAN} DNS Server IP Address: " dns_address
        if ! valid_ip $dns_address ; then
          echo "That's not a valid IPv4 address"
        else
          break
        fi
      done
    fi

    if [ -z "${MTU}" ] ;then
      while true; do
        read -n 1 -p "Do you want 9K MTU? [y|n]" yn
        case $yn in
          [Yy]* ) MTU=9000; echo 'MTU will be set to 8950, configure your VMs appropriately'; break;;
          [Nn]* ) echo 'MTU will remain default, it is recommened to set VM MTU to 1450';
        esac
      done
    fi

    if [ $# -eq 1 ] ;then
      echo -e "IP Address: $ip_address\nNetmask: $ip_netmask\nGateway: $ip_gateway\nDNS: $dns_address\nMTU: ${MTU:-1500}\n"
      read -n 1 -p "Is this correct [y|n]" yn
      case $yn in
        [Yy]* ) break;;
        [Nn]* ) echo "Try again."
      esac
    else
      break
    fi
  done

  initial_interface=`grep 'auto eth' /etc/network/interfaces | head -1 | awk '{print $2}'`
  if [ ! -z "$initial_interface" ] ;then
    sed -e '/gateway/d ' -i /etc/network/interfaces
    dns_search=`grep dns-search /etc/network/interfaces | awk '{print $2}'`
    if [ -z "`ifconfig -a | grep $initial_interface | grep $VLAN`" ] ;then
      vconfig add $initial_interface $VLAN
    fi
    cat >> /etc/network/interfaces <<EOF
auto $initial_interface.$VLAN
iface $initial_interface.$VLAN inet static
  address $ip_address
  netmask $ip_netmask
  gateway $ip_gateway
  dns-nameserver $dns_address
  dns-search $dns_search
EOF
  fi

  if [ ! -z "${default_interface}" ]; then
    default_interface=$initial_interface.$VLAN
  else
    default_interface='eth0'
    echo "Setting default interface to eth0, should it be something else?  pass it with -D "
  fi
  if [ ! -z "${external_interface}" ]; then
    external_interface=$initial_interface
  else
    external_interface='eth1'
    echo "Setting external interface to eth1, should it be something else?  pass it with -E "
  fi
  if [ ! -z "$MTU" ]; then
    sed -e "/iface ${default_interface}/a \ \ mtu ${MTU}" -i /etc/network/interfaces
    sed -e "/iface ${external_interface}/a \ \ mtu ${MTU}" -i /etc/network/interfaces
  fi
fi

# Git clone puppet_openstack_builder from cisco
echo "Cloning puppet_openstack_builder branch from CiscoSystems github.com..."
if [ -d /root/puppet_openstack_builder ] ; then
  echo -e "Looks like perhaps you ran this script before? We'll try to update your os-docs directory, just in case..."
  if ! run_cmd git --git-dir=/root/puppet_openstack_builder/.git/ pull ; then
     echo "That did not work.  Perhaps rename your os-docs directory, and try again?"
     exit 1
        fi
fi

# Get a new set, as there was no previous download
if [ ! -d /root/puppet_openstack_builder ] ; then
  if ! run_cmd git clone -b icehouse https://github.com/CiscoSystems/puppet_openstack_builder /root/puppet_openstack_builder ; then
    echo "Can't run git clone!"
    exit 1
  fi
fi

if [ ! -z "$dmz" ]; then
echo 'Acquire::http::Proxy "http://10.0.149.10:3142";' >/etc/apt/apt.conf.d/01proxy
sed -e 's/openstack-repo.cisco.com/10.0.100.21/' -i /root/puppet_openstack_builder/install-scripts/install.sh
sed -e 's/openstack-repo.cisco.com/10.0.100.21/' -i /root/puppet_openstack_builder/install-scripts/cisco.install.sh

cat >> /root/puppet_openstack_builder/data/hiera_data/user.common.yaml <<EOF
coe::base::openstack_repo_location: http://10.0.100.21/openstack/cisco
coe::base::puppet_repo_location: http://10.0.100.21/openstack/puppet
EOF
fi

# add ml2 parameters
sed -e 's/disableml2: .*/disableml2: false/' \
-i /root/puppet_openstack_builder/data/hiera_data/user.common.yaml

# create scenario for lb_vxlan with no l3
if [ -f /root/puppet_openstack_builder/data/scenarios/all_in_one.yaml.orig ]; then
  echo -e "You've run this script already, please just run: \n  puppet apply -v /etc/pupppet/manifests/site.pp"
  exit 1
fi
echo "Over-write all_in_one.yaml scenario with lb_vxlan scenario (backup to .orig)"
cp /root/puppet_openstack_builder/data/scenarios/all_in_one.yaml{,.orig}
cat > /root/puppet_openstack_builder/data/scenarios/all_in_one.yaml <<EOF
#
# scenario for lb_vxlan
#
roles:
  all_in_one:
    classes:
      - coe::base
      - "nova::%{rpc_type}"
    class_groups:
      - build
      - glance_all
      - keystone_all
      - cinder_controller
      - nova_controller
      - horizon
      - "%{db_type}_database"
      - nova_compute
      - cinder_volume
      - l2_network_controller
      - test_file
  compute:
    classes:
      - coe::base
    class_groups:
      - nova_compute
      - cinder_volume
EOF

# create classgroup for l2_network_controller
echo "Create a l2_newtork_controller class_group"
cat > /root/puppet_openstack_builder/data/class_groups/l2_network_controller.yaml <<EOF
classes:
  - "%{network_service}"
  - "%{network_service}::server"
  - "%{network_service}::server::notifications"
  - "%{network_service}::config"
  - "%{network_service}::agents::metadata"
  #- "%{network_service}::agents::l3"
  #- "%{network_service}::agents::lbaas"
  #- "%{network_service}::agents::vpnaas"
  - "%{network_service}::agents::dhcp"
  #- "%{network_service}::services::fwaas"
  - vxlan_lb::ml2
EOF

echo "Fix install.sh script to include cobbler_server in all_in_one/lb_vxlan model"
sed -e '/cobbler_server/d ' -i /root/puppet_openstack_builder/install-scripts/install.sh

if [ ! -z ${default_interface} ] ;then
echo "Setting default interface (API Interface) to $default_interface"

sed -e "s/default_interface:-eth0/default_interface:-${default_interface}/" \
  -i /root/puppet_openstack_builder/install-scripts/install.sh
  if [ -z "`grep auto\ ${default_interface} /etc/network/interfaces`" ] ;then
    unset run_all_in_one
    echo -e "\n\nNOTE: Your API Interface does not appear in /etc/network/interfaces\n\n\
    You need to address this or the next phase of installation will fail!!\n\n\n\n"
  fi
  if [ ! -z "$MTU" ]; then
    sed -e "/iface ${default_interface}/a \ \ mtu ${MTU}" -i /etc/network/interfaces
  fi
fi

if [ ! -z ${external_interface} ] ;then
echo "Setting external interface (Neutron Flat Network) to $external_interface"
sed -e "s/external_interface:-eth1/external_interface:-${external_interface}/" \
  -i /root/puppet_openstack_builder/install-scripts/install.sh
  if [ -z "`grep ${external_interface} /etc/network/interfaces`" ] ;then
    cat >> /etc/network/interfaces <<EOF
auto ${external_interface}
iface ${external_interface} inet manual
  up ip link set ${external_interface} promisc on
EOF
    if [ ! -z "$MTU" ]; then
      sed -e "/iface ${external_interface}/a \ \ mtu ${MTU}" -i /etc/network/interfaces
    fi
  fi
fi

if [ ! -z "${ntp_address}" ] ;then
sed -e "s/pool.ntp.org/${ntp_address}/" \
  -i /root/puppet_openstack_builder/install-scripts/install.sh
fi

sed -e 's/ovs/linuxbridge/' -i /root/puppet_openstack_builder/data/global_hiera_params/common.yaml

echo "Add VXLan configuration to default user.yaml for all_in_one/lb_vxlan"
sed -e '/neutron::agents/a \
openstack_release: icehouse\
service_plugins: \
horizon_neutron_options: \
enable_lbaas: false\
enable_fwaas: false\
enable_vpnaas: false\
vni_ranges:\
 - 100:10000\
vxlan_group: 229.1.2.3\
flat_networks:\
neutron::agents::linuxbridge::network_vlan_ranges:\
neutron::agents::linuxbridge::physical_interface_mappings:\
' -i /root/puppet_openstack_builder/install-scripts/install.sh

for n in `echo $interfaces | sed -e 's/:/ /g'` ; do
  iface_id=`echo $n | sed -e 's/\([0-9]*\)/\1/'`
  sed -e "/flat_networks/a \ -\ physnet${iface_id}" -i /root/puppet/openstack_builder/install-scripts/install.sh
  sed -e "/network_vlan_ranges/a \ -\ physnet${iface_id}" -i /root/puppet/openstack_builder/install-scripts/install.sh
  sed -e "/physical_interface_mappings/a \ -\ physnet${iface_id}:${n}" -i /root/puppet/openstack_builder/install-scripts/install.sh
done

echo "Setup Ml2_plugin network_plugin yaml"
cat > /root/puppet_openstack_builder/data/hiera_data/network_plugin/ml2_lb_vxlan.yaml <<EOF
neutron::core_plugin: neutron.plugins.ml2.plugin.Ml2Plugin

nova::compute::neutron::libvirt_vif_driver: nova.virt.libvirt.vif.LibvirtGenericVIFDriver
neutron::agents::l3::interface_driver: neutron.agent.linux.interface.BridgeInterfaceDriver
neutron::agents::dhcp::interface_driver: neutron.agent.linux.interface.BridgeInterfaceDriver
EOF

cat > /root/puppet_openstack_builder/data/data_mappings/tenant_network_type/vxlan.yaml <<EOF
external_interface:
 - vxlan_lb::ml2_agent::external_interface
internal_ip:
 - vxlan_lb::ml2::local_ip
 - vxlan_lb::ml2_agent::local_ip
vni_ranges:
 - vxlan_lb::ml2::vni_ranges
 - vxlan_lb::ml2_agent::vni_ranges
vxlan_group:
 - vxlan_lb::ml2::vxlan_group
 - vxlan_lb::ml2_agent::vxlan_group
flat_networks:
 - vxlan_lb::ml2::flat_networks
physical_interface_mappings:
 - vxlan_lb::ml2_agent::physical_interface_mappings
EOF

echo "Remove network::agents plugin from nova_compute.yaml classgroup"
sed -e '/agents/d ' -i /root/puppet_openstack_builder/data/class_groups/nova_compute.yaml
sed -e '/"%{network_service/a \ \ - vxlan_lb::ml2_agent' \
-i /root/puppet_openstack_builder/data/class_groups/nova_compute.yaml
sed -e '/nova::newtork/d ' -i /root/puppet_openstack_builder/data/class_groups/nova_controller.yaml

echo "Remove collectd and graphite"
sed -e '/collectd/d ' -i /root/puppet_openstack_builder/data/class_groups/build.yaml
sed -e '/graphite/d ' -i /root/puppet_openstack_builder/data/class_groups/build.yaml

sed -e 's/network_plugin: .*/network_plugin: ml2_lb_vxlan/' \
  -i /root/puppet_openstack_builder/data/global_hiera_params/common.yaml
sed -e 's/tenant_network_type: .*/tenant_network_type: vxlan/' \
  -i /root/puppet_openstack_builder/data/global_hiera_params/common.yaml

if [ ! -z "${MTU}" ] ;then
  sed -e "/openstack_release/a neutron::network_device_mtu: ${MTU}" \
    -i /root/puppet_openstack_builder/install-scripts/install.sh
  sed -e "/openstack_release/a nova::network_device_mtu: ${MTU}" \
    -i /root/puppet_openstack_builder/install-scripts/install.sh

  cat > /root/puppet_openstack_builder/install-scripts/fix_mtu.sh <<EOF
#!/bin/bash
# added to addresss: https://bugs.launchpad.net/puppet-neutron/+bug/1329643
if [ -z "\`grep network_device_mtu /usr/share/puppet/modules/neutron/manifests/init.pp\`"] ;then
  sed -e '/DEFAULT\/dhcp_agents/a \ \ \ \ "DEFAULT/network_device_mtu":      value => \$network_device_mtu;' \
    -i /usr/share/puppet/modules/neutron/manifests/init.pp
  sed -e '/\$dhcp_agents_per_network.*=/a \ \ \$network_device_mtu          = "None",'\
    -i /usr/share/puppet/modules/neutron/manifests/init.pp
fi
EOF

  chmod +x /root/puppet_openstack_builder/install-scripts/fix_mtu.sh
  sed -e '/puppet plugin/a /root/puppet_openstack_builder/install-scripts/fix_mtu.sh' \
  -i /root/puppet_openstack_builder/install-scripts/install.sh
fi

echo "Add VXLan+LinuxBridge module to puppet_openstack_builder and copy over modules"
if [ ! -d /root/puppet_openstack_builder/modules ] ;then
  mkdir -p /root/puppet_openstack_builder/modules
fi
tar xfz vxlan_lb.tgz -C /root/puppet_openstack_builder/modules/

sed -e '/builder\/manifests/a cp -R ~\/puppet_openstack_builder\/modules \/etc\/puppet\/' \
  -i /root/puppet_openstack_builder/install-scripts/install.sh

# Run all_in_one deployment?
if [ ! -z "${run_all_in_one}" ] ;then
  cd /root/puppet_openstack_builder/install-scripts
  /root/puppet_openstack_builder/install-scripts/install.sh
fi


#reboot
