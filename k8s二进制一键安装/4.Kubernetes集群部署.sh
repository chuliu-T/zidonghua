#!/bin/bash


red=$(tput setaf 1)  # 红色
green=$(tput setaf 2) # 绿色
reset=$(tput sgr0)   # 颜色重置


# 配置ansible hosts
echo -e "${green}#配置ansible hosts... ${reset}"
cat >> /etc/ansible/hosts <<EOF
[master]
192.168.100.132
192.168.100.133
192.168.100.134
[work]
192.168.100.132
192.168.100.133
192.168.100.134
EOF

# pod ip
service_ip_range=10.244.0.0 
service_ip=10.244.0.1
# service ip
cluster_ip_range=10.96.0.0
cluster_ip=10.96.0.1

cd /data/k8s-work/

echo -e "${green}#下载k8s... ${reset}"
wget http://123.60.152.160/k8s/kubernetes-server-linux-amd64.tar.gz

echo -e "${green}#解压k8s... ${reset}"
tar -xf kubernetes-server-linux-amd64.tar.gz

# 安装二进制k8s应用
cd kubernetes/server/bin/

chmod +x kube*

# 分发二进制包
echo -e "${green}#分发master二进制软件... ${reset}"
ansible master -m copy -a "src=/data/k8s-work/kubernetes/server/bin/kube-apiserver dest=/usr/local/bin/ backup=yes  mode=770"
ansible master -m copy -a "src=/data/k8s-work/kubernetes/server/bin/kube-controller-manager dest=/usr/local/bin/ backup=yes mode=770"
ansible master -m copy -a "src=/data/k8s-work/kubernetes/server/bin/kube-scheduler dest=/usr/local/bin/ backup=yes mode=770"
ansible master -m copy -a "src=/data/k8s-work/kubernetes/server/bin/kubectl dest=/usr/local/bin/ backup=yes mode=770"


# 分发工作二进制包
echo -e "${green}#分发工作二进制软件... ${reset}"
ansible work -m copy -a "src=/data/k8s-work/kubernetes/server/bin/kube-proxy dest=/usr/local/bin/ backup=yes mode=770"
ansible work -m copy -a "src=/data/k8s-work/kubernetes/server/bin/kubelet dest=/usr/local/bin/ backup=yes mode=770"


# 所有集群节点创建目录
echo -e "${green}# 所有集群创建目录... ${reset}"
ansible all -m file -a "path=/etc/kubernetes/ state=directory"
ansible all -m file -a "path=/etc/kubernetes/ssl/ state=directory"
ansible all -m file -a "path=/var/log/kubernetes/ state=directory"

ip_list=$(awk '/^\[master\]/{flag=1;next}/^\[/{flag=0}flag && NF{print "    \""$0"\","}' /etc/ansible/hosts)


# 部署api-server
cd /data/k8s-work/
echo -e "${green}#部署api-server... ${reset}"
cat > kube-apiserver-csr.json << EOF
{
"CN": "kubernetes",
  "hosts": [
    "127.0.0.1",
$ip_list
    "$cluster_ip",
    "$service_ip",
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local"
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
      "O": "kubemsb",
      "OU": "CN"
    }
  ]
}
EOF

# 生成apiserver证书及token文件
echo -e "${green}# 生成apiserver证书及token文件... ${reset}"
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-apiserver-csr.json | cfssljson -bare kube-apiserver

cat > token.csv << EOF
$(head -c 16 /dev/urandom | od -An -t x | tr -d ' '),kubelet-bootstrap,10001,"system:kubelet-bootstrap"
EOF



#  创建apiserver服务管理配置文件
echo -e "${green}# 创建apiserver服务管理配置文件... ${reset}"
cat > /etc/systemd/system/kube-apiserver.service << "EOF"
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes
After=etcd.service
Wants=etcd.service

[Service]
EnvironmentFile=-/etc/kubernetes/kube-apiserver.conf
ExecStart=/usr/local/bin/kube-apiserver $KUBE_APISERVER_OPTS
Restart=on-failure
RestartSec=5
Type=notify
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# 同步文件到集群k8s节点
echo -e "${green}# 同步文件到集群k8s节点... ${reset}"
cd /data/k8s-work/

ls /data/k8s-work/ca*.pem
ansible master  -m copy -a "src=/data/k8s-work/ca-key.pem  dest=/etc/kubernetes/ssl/ backup=yes"
ansible master  -m copy -a "src=/data/k8s-work/ca.pem  dest=/etc/kubernetes/ssl/ backup=yes"

ansible master  -m copy -a "src=/data/k8s-work/kube-apiserver.pem  dest=/etc/kubernetes/ssl/ backup=yes"
ansible master  -m copy -a "src=/data/k8s-work/kube-apiserver-key.pem  dest=/etc/kubernetes/ssl/ backup=yes"

ansible master  -m copy -a "src=/data/k8s-work/token.csv  dest=/etc/kubernetes/ backup=yes"

ansible master -m copy -a "src=/etc/systemd/system/kube-apiserver.service dest=/etc/systemd/system/kube-apiserver.service backup=yes"



# 创建apiserver服务配置文件
echo -e "${green}# 创建apiserver服务配置文件... ${reset}"
mkdir /etc/ansible/template
cat > /etc/ansible/template/kube-apiserver.conf.j2 <<EOF
   KUBE_APISERVER_OPTS="--enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \
     --anonymous-auth=false \
     --bind-address={{ target }} \
     --secure-port=6443 \
     --advertise-address={{ target }} \
     --insecure-port=0 \
     --authorization-mode=Node,RBAC \
     --runtime-config=api/all=true \
     --enable-bootstrap-token-auth \
     --service-cluster-ip-range=$cluster_ip_range/16 \
     --token-auth-file=/etc/kubernetes/token.csv \
     --service-node-port-range=30000-32767 \
     --tls-cert-file=/etc/kubernetes/ssl/kube-apiserver.pem \
     --tls-private-key-file=/etc/kubernetes/ssl/kube-apiserver-key.pem \
     --client-ca-file=/etc/kubernetes/ssl/ca.pem \
     --kubelet-client-certificate=/etc/kubernetes/ssl/kube-apiserver.pem \
     --kubelet-client-key=/etc/kubernetes/ssl/kube-apiserver-key.pem \
     --service-account-key-file=/etc/kubernetes/ssl/ca-key.pem \
     --service-account-signing-key-file=/etc/kubernetes/ssl/ca-key.pem \
     --service-account-issuer=api \
     --etcd-cafile=/etc/etcd/ssl/ca.pem \
     --etcd-certfile=/etc/etcd/ssl/etcd.pem \
     --etcd-keyfile=/etc/etcd/ssl/etcd-key.pem \
     --etcd-servers={% for etcd in etcdservers %}https://{{ etcd }}:2379{% if not loop.last %},{% endif %}{% endfor %} \
     --enable-swagger-ui=true \
     --allow-privileged=true \
     --apiserver-count=3 \
     --audit-log-maxage=30 \
     --audit-log-maxbackup=3 \
     --audit-log-maxsize=100 \
     --audit-log-path=/var/log/kube-apiserver-audit.log \
     --event-ttl=1h \
     --alsologtostderr=true \
     --logtostderr=false \
     --log-dir=/var/log/kubernetes \
     --v=4"
EOF

mkdir /etc/ansible/playbook/
cat >  /etc/ansible/playbook/configure-kube-apiserver.yaml <<EOF
---
- name: Configure Kubernetes API Server
  hosts: master
  tasks:
    - name: Create apiserver service configuration file
      template:
        src: /etc/ansible/template/kube-apiserver.conf.j2
        dest: /etc/kubernetes/kube-apiserver.conf
      vars:
        target: "{{ inventory_hostname  }}"
        etcdservers: "{{ groups['etcd'] }}"
EOF


ansible-playbook /etc/ansible/playbook/configure-kube-apiserver.yaml


ansible master -m command -a 'systemctl daemon-reload'
ansible master -m command -a 'systemctl enable --now kube-apiserver'
ansible master -m command -a 'systemctl status kube-apiserver'

# 测试
ip_list=$(awk '/^\[master\]/{flag=1;next}/^\[/{flag=0}flag && NF' /etc/ansible/hosts)


for ip in $ip_list; do
  curl --insecure https:$ip:6443/
done