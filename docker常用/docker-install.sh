
# 

tar zxf docker-23.0.6.tgz

sudo cp docker/* /usr/bin/

cat >>/usr/lib/systemd/system/docker.service <<EOF

[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/dockerd
ExecReload=/bin/kill -s HUP $MAINPID
LimitNOFILE=infinity
LimitNPROC=infinity
TimeoutStartSec=0
Delegate=yes
KillMode=process
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s

[Install]
WantedBy=multi-user.target
EOF


systemctl  daemon-reload

systemctl enable --now docker



mkdir -p /etc/docker/


