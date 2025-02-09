
#!/bin/bash

red=$(tput setaf 1)  # 红色
green=$(tput setaf 2) # 绿色
reset=$(tput sgr0)   # 颜色重置


ip_list=$(awk '/^\[master\]/{flag=1;next}/^\[/{flag=0}flag && NF{print "      \""$0"\","}' /etc/ansible/hosts)



leader=192.168.100.132


# 工作目录
cd /data/k8s-work/

# 部署kube-scheduler
echo -e "${green}# 部署kube-scheduler... ${reset}"
# 创建kube-scheduler证书请求文件
echo -e "${green}# 创建kube-scheduler证书请求文件... ${reset}"
cat > kube-scheduler-csr.json << EOF
{
    "CN": "system:kube-scheduler",
    "hosts": [
$ip_list
      "127.0.0.1"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
      {
        "C": "CN",
        "ST": "Beijing",
        "L": "Beijing",
        "O": "system:kube-scheduler",
        "OU": "system"
      }
    ]
}
EOF

# 生成kube-scheduler证书
echo -e "${green}# 生成kube-scheduler证书... ${reset}"
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-scheduler-csr.json | cfssljson -bare kube-scheduler

# 查看生成的证书
echo -e "${green}# 查看生成的证书... ${reset}"
ll | grep sch*


# 创建kube-scheduler的kubeconfig
echo -e "${green}# 创建kubectl证书请求文件... ${reset}"
kubectl config set-cluster kubernetes --certificate-authority=ca.pem --embed-certs=true --server=https://$leader:6443 --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-credentials system:kube-scheduler --client-certificate=kube-scheduler.pem --client-key=kube-scheduler-key.pem --embed-certs=true --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-context system:kube-scheduler --cluster=kubernetes --user=system:kube-scheduler --kubeconfig=kube-scheduler.kubeconfig

kubectl config use-context system:kube-scheduler --kubeconfig=kube-scheduler.kubeconfig

# 创建服务配置文件
echo -e "${green}# 创建kubectl证书请求文件... ${reset}"
cat > kube-scheduler.conf << "EOF"
KUBE_SCHEDULER_OPTS="--address=127.0.0.1 \
--kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \
--leader-elect=true \
--alsologtostderr=true \
--logtostderr=false \
--log-dir=/var/log/kubernetes \
--v=2"
EOF

# 创建服务启动配置文件
echo -e "${green}# 创建服务启动配置文件... ${reset}"
cat > kube-scheduler.service << "EOF"
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-/etc/kubernetes/kube-scheduler.conf
ExecStart=/usr/local/bin/kube-scheduler $KUBE_SCHEDULER_OPTS
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 同步文件至集群master节点
echo -e "${green}# 创建kubectl证书请求文件... ${reset}"
ansible master -m copy -a "src=/data/k8s-work/kube-scheduler.pem dest=/etc/kubernetes/ssl/ backup=yes"
ansible master -m copy -a "src=/data/k8s-work/kube-scheduler-key.pem dest=/etc/kubernetes/ssl/ backup=yes"
ansible master -m copy -a "src=/data/k8s-work/kube-scheduler.kubeconfig dest=/etc/kubernetes/"
ansible master -m copy -a "src=/data/k8s-work/kube-scheduler.conf dest=/etc/kubernetes/"
ansible master -m copy -a "src=/data/k8s-work/kube-scheduler.service dest=/usr/lib/systemd/system/"


# 2.5.8.7 启动服务
echo -e "${green}# 创建kubectl证书请求文件... ${reset}"
ansible master  -a "systemctl daemon-reload"
ansible master  -a "systemctl enable --now kube-scheduler"
ansible master  -a "systemctl status kube-scheduler"