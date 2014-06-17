#!/bin/bash

source ~/openrc

nova delete vxa
if [ $? ] ; then echo Deleted vxa; fi
nova delete vxb
if [ $? ] ; then echo Deleted vxb; fi

neutron net-delete sharednet1

neutron net-delete tenantnet1

glance image-delete trusty
if [ $? ] ; then echo Deleted trusty; fi
