#!/bin/bash
# grab the puppet_openstack_builder code
# and update it if it doesn't have the right
# elements already defined for VLAN/VXLan/LB
# 
# Also, create a new scenario, and role mapping
# for this enviornment

set -o errexit

usage() {
cat <<EOF
usage: $0 options

OPTIONS:
-h Show this message
-p {proxy_address} http proxy i.e. -p http://username:password@host:port/
-s {vlan} single interface vlan to enable
EOF
}
export -f usage


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
while getopts "h:p:s:" OPTION
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
    s)
      VLAN=$OPTARG
      export vlan=$VLAN
      ;;
  esac
done

# Make sure the apt repository list is up to date
echo -e "\n\nUpdate apt repository...\n\n"
if ! run_cmd apt-get $APT_CONFIG update; then
  echo "Can't update apt repository"
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

echo "Enable 8021q module for VLAN config"
if ! $(run_cmd echo 8021q >> /etc/modules ) || ! $(run_cmd modprobe 8021q) ; then
  echo "Unable to install 8021q module"
  exit 1
fi

if [ ${VLAN} ] ; then
  while true; do
    while true; do
      read -ep "Enter the VLAN:${VLAN} IPv4 Address: " ip_address
      if ! valid_ip $ip_address ; then
        echo "That's not an IP address"
      else
        break
      fi
    done

    while true; do
      read -ep "Enter the VLAN:${VLAN} Netmask: " ip_netmask
      if ! valid_ip $ip_netmask ; then
        echo "That's not a valid IPv4 Netmask"
      else
        break
      fi
    done

    while true; do
      read -ep "Enter the VLAN:${VLAN} IPv4 Gateway: " ip_gateway
      if ! valid_ip $ip_gateway ; then
        echo "That's not a valid IPv4 address"
      else
        break
      fi
    done

    while true; do
      read -ep "Enter the initial VLAN:${VLAN} DNS Server IP Address: " dns_address
      if ! valid_ip $dns_address ; then
        echo "That's not a valid IPv4 address"
      else
        break
      fi
    done

    echo "IP Address: $ip_address, Netmask: $ip_netmask, Gateway: $ip_gateway, DNS: $dns_address"
    read -n 1 -p "Is this correct [y|n]" yn
    case $yn in
      [Yy]* ) break;;
      [Nn]* ) echo "Try again."
    esac
  done
fi
