#!/bin/bash
# grab the puppet_openstack_builder code
# and update it if it doesn't have the right
# elements already defined for VLAN/VXLan/LB
# 
# Also, create a new scenario, and role mapping
# for this enviornment
exec > >(tee /var/log/lb_vxlan_client_setup.log)
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
-P {puppet_server}  FQDN of the puppet master
-I {puppet_ip}      IP of the puppet master

The script expects at least one parameter, so at a minimum pass -t to set
the ntp server to something other than 1.pool.ntp.com

more commonly, you may want to use a different Default interface (for API endpoint)
or set the MTU on an interface (the "external" interface).

If you have multiple interfaces, and want the OpenStack config to include them
pass them as a colon separated list to the -I parameter (not this should include
  any interface you pass as the -E parameter as they set different components of
  the environment).

An example, with the default interface on eth1, the large MTU interface as eth3, and
eth2 and eth4 also being created:

./client_setup.sh -t ntp.esl.cisco.com -m -D eth1 -E eth3 -P build.lab I 10.0.0.10 -r
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
while getopts "hmrp:v:i:n:g:d:t:D:E:P:I:" OPTION
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
      export puppet_ip=$OPTARG
      ;;
    P)
      export puppet_server=$OPTARG
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

if [ ! -z "$dmz" ]; then
echo 'Acquire::http::Proxy "http://10.0.149.10:3142";' >/etc/apt/apt.conf.d/01proxy
export repo_location=10.0.100.21
fi

## Setup Cisco Repos
REPO_LOC=${repo_location:-openstack-repo.cisco.com}
# Add Cisco repo and puppet repo
cat > /etc/apt/sources.list.d/cisco-openstack-mirror_icehouse.list<<EOF
# cisco-openstack-mirror_icehouse
deb http://$REPO_LOC/openstack/cisco icehouse/snapshots/i.0 main
deb-src http://$REPO_LOC/openstack/cisco icehouse/snapshots/i.0 main
EOF

cat > /etc/apt/sources.list.d/cisco-openstack-puppet_icehouse.list<<EOF
# cisco packaged puppet modules
deb http://$REPO_LOC/openstack/puppet icehouse main
deb-src http://$REPO_LOC/openstack/puppet icehouse main
EOF

# Add the signing key for the Cisco OpenStack repo
echo '-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v1.4.11 (GNU/Linux)

mQENBE/oXVkBCACcjAcV7lRGskECEHovgZ6a2robpBroQBW+tJds7B+qn/DslOAN
1hm0UuGQsi8pNzHDE29FMO3yOhmkenDd1V/T6tHNXqhHvf55nL6anlzwMmq3syIS
uqVjeMMXbZ4d+Rh0K/rI4TyRbUiI2DDLP+6wYeh1pTPwrleHm5FXBMDbU/OZ5vKZ
67j99GaARYxHp8W/be8KRSoV9wU1WXr4+GA6K7ENe2A8PT+jH79Sr4kF4uKC3VxD
BF5Z0yaLqr+1V2pHU3AfmybOCmoPYviOqpwj3FQ2PhtObLs+hq7zCviDTX2IxHBb
Q3mGsD8wS9uyZcHN77maAzZlL5G794DEr1NLABEBAAG0NU9wZW5TdGFja0BDaXNj
byBBUFQgcmVwbyA8b3BlbnN0YWNrLWJ1aWxkZEBjaXNjby5jb20+iQE4BBMBAgAi
BQJP6F1ZAhsDBgsJCAcDAgYVCAIJCgsEFgIDAQIeAQIXgAAKCRDozGcFPtOxmXcK
B/9WvQrBwxmIMV2M+VMBhQqtipvJeDX2Uv34Ytpsg2jldl0TS8XheGlUNZ5djxDy
u3X0hKwRLeOppV09GVO3wGizNCV1EJjqQbCMkq6VSJjD1B/6Tg+3M/XmNaKHK3Op
zSi+35OQ6xXc38DUOrigaCZUU40nGQeYUMRYzI+d3pPlNd0+nLndrE4rNNFB91dM
BTeoyQMWd6tpTwz5MAi+I11tCIQAPCSG1qR52R3bog/0PlJzilxjkdShl1Cj0RmX
7bHIMD66uC1FKCpbRaiPR8XmTPLv29ZTk1ABBzoynZyFDfliRwQi6TS20TuEj+ZH
xq/T6MM6+rpdBVz62ek6/KBcuQENBE/oXVkBCACgzyyGvvHLx7g/Rpys1WdevYMH
THBS24RMaDHqg7H7xe0fFzmiblWjV8V4Yy+heLLV5nTYBQLS43MFvFbnFvB3ygDI
IdVjLVDXcPfcp+Np2PE8cJuDEE4seGU26UoJ2pPK/IHbnmGWYwXJBbik9YepD61c
NJ5XMzMYI5z9/YNupeJoy8/8uxdxI/B66PL9QN8wKBk5js2OX8TtEjmEZSrZrIuM
rVVXRU/1m732lhIyVVws4StRkpG+D15Dp98yDGjbCRREzZPeKHpvO/Uhn23hVyHe
PIc+bu1mXMQ+N/3UjXtfUg27hmmgBDAjxUeSb1moFpeqLys2AAY+yXiHDv57ABEB
AAGJAR8EGAECAAkFAk/oXVkCGwwACgkQ6MxnBT7TsZng+AgAnFogD90f3ByTVlNp
Sb+HHd/cPqZ83RB9XUxRRnkIQmOozUjw8nq8I8eTT4t0Sa8G9q1fl14tXIJ9szzz
BUIYyda/RYZszL9rHhucSfFIkpnp7ddfE9NDlnZUvavnnyRsWpIZa6hJq8hQEp92
IQBF6R7wOws0A0oUmME25Rzam9qVbywOh9ZQvzYPpFaEmmjpCRDxJLB1DYu8lnC4
h1jP1GXFUIQDbcznrR2MQDy5fNt678HcIqMwVp2CJz/2jrZlbSKfMckdpbiWNns/
xKyLYs5m34d4a0it6wsMem3YCefSYBjyLGSd/kCI/CgOdGN1ZY1HSdLmmjiDkQPQ
UcXHbA==
=v6jg
-----END PGP PUBLIC KEY BLOCK-----' | apt-key add -

# add cisco puppet repo key

echo '-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v1.4.11 (GNU/Linux)

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
ykz5a/8840rWqc7sLA7lKA==
=HVuX
-----END PGP PUBLIC KEY BLOCK-----' | apt-key add -


apt-get update && apt-get install -y ipmitool

# Fix puppet, clobbering any existing puppet version to ensure
# PKI gets set up correctly.
apt-get remove --purge --yes puppet puppet-common
rm -rf /etc/puppet/puppet.conf /var/lib/puppet

apt-get install puppet -y

if [ ! -z "${puppet_server}" ] ;then
sed -e "/logdir/ a pluginsync=true" -i /etc/puppet/puppet.conf ; \
sed -e "/logdir/ a server=aio8.onecloud" -i /etc/puppet/puppet.conf ; \
else
  echo "set server={puppet server hostname} and pluginsync=true in /etc/puppet/puppet.conf"
  echo "and ensure that the puppet server fqdn is configured in /etc/hosts or in upstream DNS!"
fi

if [ ! -z ${default_interface} ] ;then
echo "Setting default interface (API Interface) to $default_interface"

  if [ -z "`grep auto\ ${default_interface} /etc/network/interfaces`" ] ;then
    unset run_all_in_one
    echo -e "\n\nNOTE: Your API Interface does not appear in /etc/network/interfaces\n\n\
    You need to address this or the next phase of installation will fail!!\n\n\n\n"
    exit 1
  fi
  # if [ ! -z "$MTU" ]; then
  #   sed -e "/iface ${default_interface}/a \ \ mtu ${MTU}" -i /etc/network/interfaces
  # fi
fi

if [ ! -z ${external_interface} ] ;then
echo "Setting external interface (Neutron Flat Network) to $external_interface"
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
  apt-get install -y ntp
  echo "server ${ntp_address} iburst" >/etc/ntp.conf
  service ntp restart
  ntpq -p
fi


# Run all_in_one deployment?
if [ ! -z "${run_all_in_one}" ] ;then
  puppet agent -v -d -t
fi


#reboot
