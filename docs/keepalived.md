# Purpose of Keepalived Implementation

Adding support for [keepalived](http://www.keepalived.org/documentation.html) to enable high availability in an HAProxy deployment, leveraging the [Virtual Router Redundancy Protocol](https://en.wikipedia.org/wiki/Virtual_Router_Redundancy_Protocol), formally specified in [RFC 5798](https://tools.ietf.org/html/rfc5798). See the [keepalived man page](https://linux.die.net/man/5/keepalived.conf) for more details on keepalived capabilities, as well as the [keepalived user manual](http://www.keepalived.org/pdf/UserGuide.pdf).

This enables declaring a virtual IP (`keepalived.vip`) that will automatically fail over between the multiple HAProxy VMs: the master will initially be the BOSH VM for HAProxy job instance 0. The default IP addresses assigned by BOSH to VMs on eth0 are used within the VRRP protocol.

Prerequisites:
 * The HAProxy VMs must be within the same broadcast domain, i.e. receive multicast traffic sent to the 224.0.0.18 broadcast and IP protocol number 112.
 * The clients using this VIP must be within the [same broadcast domain](https://en.wikipedia.org/wiki/Broadcast_domain) as the HAProxy VMs and accepting gratuitous ARP.


# This feature has been successfully tested on the following IaaS:
* Cloudstack w/ XenServer


# Limitations and Future Enhancements
* Log collection and monitoring/alerting: keepalived logs are sent to syslog and cannot be retrieved using `bosh logs`. You have to tail `/var/log/syslog` to get info.
* Health check period is hardcoded to 2s. We will add a parameter for this.
* mcast_src_ip address is 224.0.0.18. We will add a parameter for this.
* No email notification yet. We will add a parameter for this.
* Hardcoded VRRP advertisement interval to 1s (advert_int), triggering a new VRRP election and failover. No drain script handling yet to prevent downtime while BOSH upgrades.
* For the moment, keepalived is configured to use broadcast for network communication between nodes. Future versions will be able to use unicast to expose a VIP or control a distinct SDN system such as an AWS Elastic IP (through custom VRRP failover notification scripts).


# Testing
## First Verification
* After setting up the `keepalived.vip` parameter, connect to the instance with index 0 of your AZ. BOSH will configure this one as master.
* Run `sudo ip a`.
* You should see the VIP (in the example above, VIP is set to 10.234.250.201):

```
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 06:c9:f6:00:0a:38 brd ff:ff:ff:ff:ff:ff
    inet 10.234.250.199/26 brd 10.234.250.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet 10.234.250.201/32 scope global eth0
       valid_lft forever preferred_lft forever
```
* The VIP is up. You can perform further testing and access your backend services using the VIP.

## Failover Scenario
* Stop HAProxy on the first node by running `monit stop haproxy`.
* Run `ip a` on the first node:
```
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 06:c9:f6:00:0a:38 brd ff:ff:ff:ff:ff:ff
    inet 10.234.250.199/26 brd 10.234.250.255 scope global eth0
       valid_lft forever preferred_lft forever
```
* No more VIP. Let's look at the second node:
```
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 06:38:ce:00:0a:39 brd ff:ff:ff:ff:ff:ff
    inet 10.234.250.200/26 brd 10.234.250.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet 10.234.250.201/32 scope global eth0
       valid_lft forever preferred_lft forever
```
* It works! If we look at logs on the first node:
```
Dec  7 12:47:34 localhost Keepalived_vrrp[4558]: VRRP_Script(check_haproxy) failed
Dec  7 12:47:34 localhost Keepalived_vrrp[4558]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Effective priority = 101
Dec  7 12:47:35 localhost Keepalived_vrrp[4558]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Received higher prio advert 102
Dec  7 12:47:35 localhost Keepalived_vrrp[4558]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Entering BACKUP STATE
```
and the second node:
```
Dec  7 12:47:35 localhost Keepalived_vrrp[4544]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) forcing a new MASTER election
Dec  7 12:47:36 localhost Keepalived_vrrp[4544]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Transition to MASTER STATE
Dec  7 12:47:37 localhost Keepalived_vrrp[4544]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Entering MASTER STATE
```
* Same scenario if you stop the master node:
```
Dec  7 12:55:52 localhost Keepalived_vrrp[4544]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Received higher prio advert 103
Dec  7 12:55:52 localhost Keepalived_vrrp[4544]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Entering BACKUP STATE
Dec  7 12:58:22 localhost Keepalived_vrrp[4544]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Transition to MASTER STATE
Dec  7 12:58:23 localhost Keepalived_vrrp[4544]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Entering MASTER STATE
```
* If you kill the VM running the master node (using the IaaS):
```
Dec  8 14:01:34 localhost Keepalived_vrrp[11463]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Transition to MASTER STATE
Dec  8 14:01:35 localhost Keepalived_vrrp[11463]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Entering MASTER STATE
```
and after restarting the master node:
```
Dec  8 14:02:55 localhost Keepalived_vrrp[11463]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Received lower prio advert 101, forcing new election
Dec  8 14:02:56 localhost Keepalived_vrrp[11463]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Received higher prio advert 103
Dec  8 14:02:56 localhost Keepalived_vrrp[11463]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Entering BACKUP STATE
```
* Running the canary on the master node:
Master node:
```
Dec  8 14:13:20 localhost Keepalived_vrrp[1046]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Effective priority = 101
```

Backup node:
```
Dec  8 14:13:24 localhost Keepalived_vrrp[11463]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Transition to MASTER STATE
Dec  8 14:13:25 localhost Keepalived_vrrp[11463]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Entering MASTER STATE
Dec  8 14:13:33 localhost Keepalived_vrrp[11463]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Received lower prio advert 101, forcing new election
Dec  8 14:13:34 localhost Keepalived_vrrp[11463]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Received higher prio advert 103
Dec  8 14:13:34 localhost Keepalived_vrrp[11463]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Entering BACKUP STATE
```
