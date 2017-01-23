# Purpose of keepalived implementation

Adding support for [keepalived](http://www.keepalived.org/documentation.html) to enable high availability in an haproxy deployment, leveraging the https://en.wikipedia.org/wiki/Virtual_Router_Redundancy_Protocol more formally [RFC 5798](https://tools.ietf.org/html/rfc5798). See [keep-alived man page](https://linux.die.net/man/5/keepalived.conf) for more precision over capabilities of keep-alived as well as the [keep-alived user manual](http://www.keepalived.org/pdf/UserGuide.pdf)

This enables declaring an virtual IP (``keepalived.vip``) that will automatically fail over between the multiple haproxy VMs: the master will initially be the bosh vm for haproxy job instance 0. The default IP addresses assigned by bosh to vms on eth0 are used within the VRRP protocol.

Prereqs:
 * The haproxy VMs must be within the same broadcast domain, i.e. receive multicast traffic sent to the 224.0.0.18 broadcast and IP protocol number 112.
* The clients using this VIP must be within the [same broadcast domain](https://en.wikipedia.org/wiki/Broadcast_domain) as the haproxy vms and accepting ARP gratuitious. 


# This feature has been successfully tested on the following IAAS :
* Cloudstack w/ XenServer


# Limitations and future enhancements
* logs collection and monitoring/alerting : keepalived logs are sent to syslog and can t be retrieved using `bosh logs` you have to tail /var/log/syslog to get info
* Health check period is hardcoded to 2s : we will add parameter for this
* mcast_src_ip @IP is 224.0.0.18 : we will add parameter for this
* Not yet email notification : we will add parameter for this
* Hardcoded VRRP advertisement to 1 S (advert_int) triggering a new VRRP election and fail over. Not yet drain script handling to prevent downtime while bosh upgrades.
* For the moment, KeepAlived is configured to use broadcast for network communication between nodes. Future versions will be able to use unicast to expose a VIP or control a distinct SDN system such as an AWS ElasticIP (through custom VRRP failover notification scripts)


# testing
## First verification
* after setting up keepalived.vip parameter, connect to the instance with index 0 of your AZ. BOSH will configure this one as master
* run `sudo ip a`
* you should see the VIP (in example above, VIP is set as 10.234.250.201)

```
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 06:c9:f6:00:0a:38 brd ff:ff:ff:ff:ff:ff
    inet 10.234.250.199/26 brd 10.234.250.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet 10.234.250.201/32 scope global eth0
       valid_lft forever preferred_lft forever
```
* The VIP is up, you can perform further testing and access your backend services using the VIP

## Failover scenario
* Let s stop haproxy on first node by running `monit stop haproxy`
* Let s run `ip a` on first node
```
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 06:c9:f6:00:0a:38 brd ff:ff:ff:ff:ff:ff
    inet 10.234.250.199/26 brd 10.234.250.255 scope global eth0
       valid_lft forever preferred_lft forever
```
* no more VIP, let s look at our second node
```
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 06:38:ce:00:0a:39 brd ff:ff:ff:ff:ff:ff
    inet 10.234.250.200/26 brd 10.234.250.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet 10.234.250.201/32 scope global eth0
       valid_lft forever preferred_lft forever
```
* It works ! If we look at logs on first node :
```
Dec  7 12:47:34 localhost Keepalived_vrrp[4558]: VRRP_Script(check_haproxy) failed
Dec  7 12:47:34 localhost Keepalived_vrrp[4558]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Effective priority = 101
Dec  7 12:47:35 localhost Keepalived_vrrp[4558]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Received higher prio advert 102
Dec  7 12:47:35 localhost Keepalived_vrrp[4558]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Entering BACKUP STATE
```
and second node :
```
Dec  7 12:47:35 localhost Keepalived_vrrp[4544]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) forcing a new MASTER election
Dec  7 12:47:36 localhost Keepalived_vrrp[4544]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Transition to MASTER STATE
Dec  7 12:47:37 localhost Keepalived_vrrp[4544]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Entering MASTER STATE
```
* Same scenario if you stop the master node :
```
Dec  7 12:55:52 localhost Keepalived_vrrp[4544]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Received higher prio advert 103
Dec  7 12:55:52 localhost Keepalived_vrrp[4544]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Entering BACKUP STATE
Dec  7 12:58:22 localhost Keepalived_vrrp[4544]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Transition to MASTER STATE
Dec  7 12:58:23 localhost Keepalived_vrrp[4544]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Entering MASTER STATE
```
* If you kill the VM running the master node (using IAAS) :
```
Dec  8 14:01:34 localhost Keepalived_vrrp[11463]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Transition to MASTER STATE
Dec  8 14:01:35 localhost Keepalived_vrrp[11463]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Entering MASTER STATE
```
and after restarting the master node :
```
Dec  8 14:02:55 localhost Keepalived_vrrp[11463]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Received lower prio advert 101, forcing new election
Dec  8 14:02:56 localhost Keepalived_vrrp[11463]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Received higher prio advert 103
Dec  8 14:02:56 localhost Keepalived_vrrp[11463]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Entering BACKUP STATE
```
* Running the canary on master node :
master node :
```
Dec  8 14:13:20 localhost Keepalived_vrrp[1046]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Effective priority = 101
```

slave node :
```
Dec  8 14:13:24 localhost Keepalived_vrrp[11463]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Transition to MASTER STATE
Dec  8 14:13:25 localhost Keepalived_vrrp[11463]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Entering MASTER STATE
Dec  8 14:13:33 localhost Keepalived_vrrp[11463]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Received lower prio advert 101, forcing new election
Dec  8 14:13:34 localhost Keepalived_vrrp[11463]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Received higher prio advert 103
Dec  8 14:13:34 localhost Keepalived_vrrp[11463]: VRRP_Instance(haproxy_keepalived_mysql_infra_check_haproxy) Entering BACKUP STATE
```
