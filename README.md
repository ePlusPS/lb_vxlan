VLAN in VM with LinuxBridge and VXLan with Jumbo MTU
====================================================

Configure puppet\_openstack\_builder project to use VLANs, LinuxBridge,
and VXLan

The script in this project will update Cisco's version of 
puppet_openstack_builder (aka COI), and update it to use by default:
 - ML2 neutron core_plugin
 - Linux Bridge L2 plugin/agent
 - VXLan tenant netorks

It can also assist in configuring a VLAN as a management interface for
systems with only a single physical network interface.

It also includes an option to define the "default" or management/tunnel
interface, and the "external" or provider/neutron managed interface. It
only supports the configuration of a single neutron managed interface
at the moment.

For a standard 2 physical interface setup, where the interfaces are
already configured in the OS (e.g. dhcp or static configurations) with:
- eth0 for default
- eth1 for external
- ntp.esl.cisco.com for ntp
- Jumbo MTU (ends up at 8950 or less bytes at the VM with VXLan configured)

  git clone https://github.com/onecloud/lb\_vxlan
  cd lb\_vxlan
  ./setup -m -t ntp.esl.cisco.com -D eth0 -E eth1 -r

If you want to move a single interface to a VLAN for management (likely so that
you can use the un-tagged interface to pass tagged packets from your VMs), you
might use:

  ./setup -m -v 100 -i 10.0.100.10 -n 255.255.255.0 -g 10.0.100.1 -d 10.0.100.5

Note that the sytem will assume eth0, and add an eth0.XXX interface, and make
eth0 the default.
