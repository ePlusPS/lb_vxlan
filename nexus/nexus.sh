#!/bin/bash
# Modify the lb_vxlan environment to support the cisco_nexus
# ML2 mechanism driver

exec > >(tee /var/log/nexus_build_setup.log)
exec 2>&1
set -o errexit

usage() {
cat <<EOF
usage: $0 options

OPTIONS:
-h                  Show this message
-r  				Do not prompt, just use CLI passed parameters
-p {proxy_address}  http proxy i.e. -p http://username:password@host:port/
-m {ip:host:port:host:port} Switch 1 config with two hosts and ports
-n {ip:host:port:host:port} Switch 2 config with two hosts and ports
-u {admin_user}				Switch user
-w {admin_pass}				Switch password
-k {switch_1_host_key}		Switch 1 host ssh_key
-j {switch_2_host_key}		Switch 2 host ssh_key

This script will ask the user for information needed to configure the Cisco Nexus 
ML2 mechanism driver.
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
while getopts "hp:m:n:u:w:k:" OPTION
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
    m)
      export switch_one=$OPTARG
      ;;
    n)
      export switch_two=$OPTARG
      ;;
    u)
      export admin_user=$OPTARG
      ;;
    w)
      export admin_pass=$OPTARG
      ;;
    k)
	  export host_key_one=$OPTARG
	  ;;
    j)
	  export host_key_two=$OPTARG
	  ;;
	r)
	  export run_script=true
	  ;;
  esac
done

if [ $# -eq 0 ] ;then
  usage
  exit 1
fi


while true; do
if [ -z "$switch_one" ] ;then
  while true; do
    read -ep "Enter the switch_one IP address [${switch_one}]: " switch_one_ip
    if ! valid_ip $switch_one_ip ; then
      echo "That's not an IP address"
    else
    	switch_one=switch_one_ip
      break
    fi
  done
fi

if [ -z "$switch_two" ] ;then
  while true; do
    read -ep "Enter the switch_one IP address [${switch_two}]: " switch_two_ip
    if ! valid_ip $switch_two_ip ; then
      echo "That's not an IP address"
    else
    	switch_one=switch_two_ip
      break
    fi
  done
fi

if [ $# -gt 0 ] ;then
  echo -e "Switch One IP Address: $switch_one\n\n"
  read -n 1 -p "Is this correct [y|n]" yn
  case $yn in
    [Yy]* ) break;;
    [Nn]* ) echo "Try again."
  esac
else
  break
fi
done

