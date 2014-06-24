#!/bin/bash

## This is a stub and needs a proper front end to capture the right parameters

switch_one='10.1.64.1'
switch_two='10.1.64.2'
admin_user='admin'
admin_pass='!cisco123'
hypervisor1[0]='aio8'
hypervisor1[1]='e1/17'
hypervisor1[2]='e1/18'
hypervisor2[0]='compute8'
hypervisor2[1]='e1/47'
hypervisor2[2]='e1/48'

if [ -z "`grep ml2_cisco /etc/neutron/plugin.ini`" ]; then

sed -e 's/mechanism_drivers=/mechanism_drivers=cisco_nexus,/' -i /etc/neutron/plugin.ini
cat >> /etc/neutron/plugin.ini <<EOF
[ml2_cisco]
vlan_name_prefix = os-gen-
svi_round_robin = True
managed_physical_network = physnet1

# Cisco switch configuration(s)

EOF

fi

# switch one

echo "[ml2_mech_cisco_nexus:${switch_one}]" >> /etc/neutron/plugin.ini
for ((i=1;i<$hypervisor[@];i++)) ;do
echo "$hypervisor1[0]=$hypervisor1[$i]" >> /etc/neutron/plugin.ini
echo "$hypervisor2[0]=$hypervisor2[$i]" >> /etc/neutron/plugin.ini
done
cat >> /etc/neutron/plugin.ini
ssh_port=22
username=${admin_user}
password=${admin_pass}

EOF

#switch two

# echo "[ml2_mech_cisco_nexus:${switch_two}]" >> /etc/neutron/plugin.ini
# for ((i=1;i<$hypervisor[@];i++)) ;do
# echo "$hypervisor1[0]=$hypervisor1[$i]" >> /etc/neutron/plugin.ini
# echo "$hypervisor2[0]=$hypervisor2[$i]" >> /etc/neutron/plugin.ini
# done
# cat >> /etc/neutron/plugin.ini
# ssh_port=22
# username=${admin_user}
# password=${admin_pass}

# EOF


