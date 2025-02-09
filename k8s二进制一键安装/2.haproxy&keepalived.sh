cat >/etc/haproxy/haproxy.cfg<<"EOF"
global
    maxconn 2000
    ulimit-n 16384
    log 127.0.0.1 local0 err
    stats timeout 30s

defaults
    log global
    mode http
    option httplog
    timeout connect 5000
    timeout client 50000
    timeout server 50000
    timeout http-request 15s
    timeout http-keep-alive 15s

frontend monitor-in
    bind *:33305
    mode http
    option httplog
    monitor-uri /monitor

frontend k8s-master
    bind 0.0.0.0:6443
    bind 127.0.0.1:6443
    mode tcp
    option tcplog
    tcp-request inspect-delay 5s
    default_backend k8s-master

backend k8s-master
    mode tcp
    option tcplog
    option tcp-check
    balance roundrobin
    default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100
    server  master1  192.168.150.89:6443 check
    server  master2  192.168.150.90:6443 check
EOF

ha1:

cat >/etc/keepalived/keepalived.conf<<"EOF"
! Configuration File for keepalived
global_defs {
   router_id LVS_DEVEL
script_user root
   enable_script_security
}
vrrp_script chk_apiserver {
   script "/etc/keepalived/check_apiserver.sh"
   interval 5
   weight -5
   fall 2 
rise 1
}
vrrp_instance VI_1 {
   state MASTER
   interface ens33
   mcast_src_ip 192.168.150.93
   virtual_router_id 51
   priority 100
   advert_int 2
   authentication {
       auth_type PASS
       auth_pass K8SHA_KA_AUTH
   }
   virtual_ipaddress {
       192.168.150.100
   }
   track_script {
      chk_apiserver
   }
}
EOF


ha2:

cat >/etc/keepalived/keepalived.conf<<"EOF"
! Configuration File for keepalived
global_defs {
   router_id LVS_DEVEL
script_user root
   enable_script_security
}
vrrp_script chk_apiserver {
   script "/etc/keepalived/check_apiserver.sh"
  interval 5
   weight -5
   fall 2 
rise 1
}
vrrp_instance VI_1 {
   state BACKUP
   interface ens33
   mcast_src_ip 192.168.150.94
   virtual_router_id 51
   priority 99
   advert_int 2
   authentication {
       auth_type PASS
       auth_pass K8SHA_KA_AUTH
   }
   virtual_ipaddress {
       192.168.150.100
   }
   track_script {
      chk_apiserver
   }
}
EOF
