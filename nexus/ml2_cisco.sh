#!/bin/bash

mkdir ~neutron/.ssh
cat >> ~neutron/.ssh/known_hosts <<EOF
|1|N8KzQU0nKIAgyX/qDsZA8UA725w=|GeojME5hmoAu5m3+rx2WKghyzjA= ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAAgQDKzXfRCwUAswY6PfD/Myy7z9RbAk0LVZTpOIF8jtNonPVWbz+m2ZJ8SXjAaVsjwXOvLEHgapqyISPT8sLVtmQq+GPlx2ixZMmG5LYPPXDlsbfqh0yPdBmJ+kGIQcC4nXn1wIC+F6Zv1Yml6s4tvuFK9kzxQ4UjnS55U0in++j1Gw==
EOF
chown neutron.neutron -R ~neutron/.ssh/
chmod 700 ~neutron/.ssh

git clone https://github.com/CiscoSystems/ncclient.git /root/ncclient

(cd /root/ncclient; python ./setup.py install)
## This is a stub and needs a proper front end to capture the right parameters

switch_one='10.1.64.1'
switch_two='10.1.64.2'
admin_user='admin'
admin_pass='!cisco123'
hypervisor1[0]='aio8'
hypervisor1[1]='1/33'
#hypervisor1[2]='1/34'
hypervisor2[0]='compute8'
hypervisor2[1]='1/47'
#hypervisor2[2]='1/48'

if [ -z "`grep ml2_cisco /etc/neutron/plugins/ml2/ml2_conf.ini`" ]; then

sed -e 's/mechanism_drivers=/mechanism_drivers=cisco_nexus,/' -i /etc/neutron/plugins/ml2/ml2_conf.ini
cat >> /etc/neutron/plugins/ml2/ml2_conf.ini <<EOF
[ml2_cisco]
vlan_name_prefix = q-
svi_round_robin = False
managed_physical_network = physnet1

# Cisco switch configuration(s)

EOF

fi

# switch one
echo "[ml2_mech_cisco_nexus:${switch_one}]" >> /etc/neutron/plugins/ml2/ml2_conf.ini
for ((i=1;i<${#hypervisor1[@]};i++)) ;do
echo "${hypervisor1[0]}=${hypervisor1[$i]}" >> /etc/neutron/plugins/ml2/ml2_conf.ini
echo "${hypervisor2[0]}=${hypervisor2[$i]}" >> /etc/neutron/plugins/ml2/ml2_conf.ini
done
cat >> /etc/neutron/plugins/ml2/ml2_conf.ini <<EOF
ssh_port=22
username=${admin_user}
password=${admin_pass}

EOF

#switch two

# echo "[ml2_mech_cisco_nexus:${switch_two}]" >> /etc/neutron/plugins/ml2/ml2_conf.ini
# for ((i=1;i<${#hypervisor2[@]};i++)) ;do
# echo "${hypervisor1[0]}=${hypervisor1[$i]}" >> /etc/neutron/plugins/ml2/ml2_conf.ini
# echo "${hypervisor2[0]}=${hypervisor2[$i]}" >> /etc/neutron/plugins/ml2/ml2_conf.ini
# done
# cat >> /etc/neutron/plugins/ml2/ml2_conf.ini <<EOF
# ssh_port=22
# username=${admin_user}
# password=${admin_pass}

# EOF

for n in `ls /etc/init/neutron*`; do m=$(basename $n); o=${m%.*}; service $o restart; done


