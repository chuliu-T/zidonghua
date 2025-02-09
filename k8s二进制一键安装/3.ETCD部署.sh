#!/bin/bash


red=$(tput setaf 1)  # 红色
green=$(tput setaf 2) # 绿色
reset=$(tput sgr0)   # 颜色重置





# 安装并配置ansible工具
echo -e "${green}#安装ansible... ${reset}"
yum install -y ansible  >/dev/null
tee > /etc/ansible/hosts <<EOF
[etcd]
192.168.100.132
192.168.100.133
192.168.100.134
EOF


ansible all -b -m service -a "name=NetworkManager state=stopped"


mkdir -p /data/k8s-work
cd /data/k8s-work

# 清除残余
rm -f cfssl_linux-amd64
rm -f cfssljson_linux-amd64
rm -f  cfssl-certinfo_linux-amd64
# 获得cfssl工具
echo -e "${green}#安装ansible... ${reset}"
wget http://123.60.152.160/k8s/cfssl_linux-amd64
wget http://123.60.152.160/k8s/cfssljson_linux-amd64
wget http://123.60.152.160/k8s/cfssl-certinfo_linux-amd64

# 给她执行的权限
chmod +x cfssl* 

mv cfssl_linux-amd64 /usr/local/bin/cfssl
mv cfssljson_linux-amd64 /usr/local/bin/cfssljson
mv cfssl-certinfo_linux-amd64 /usr/local/bin/cfssl-certinfo

# 查看版本cfssl号
echo -e "${green}cfssl version ${reset}"
cfssl version

# 配置ca证书请求文件
echo -e "${green}配置ca证书请求文件 ${reset}"
cat > ca-csr.json <<"EOF"
{
  "CN": "kubernetes",
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
  ],
  "ca": {
          "expiry": "87600h"
  }
}
EOF


# 创建CA证书
echo -e "${green}创建CA证书 ${reset}"
cfssl gencert -initca ca-csr.json | cfssljson -bare ca

# 配置证书策略
echo -e "${green}配置证书策略 ${reset}"
cfssl print-defaults config > ca-config.json # 默认策略
cat > ca-config.json <<"EOF"
{
  "signing": {
      "default": {
          "expiry": "87600h"
        },
      "profiles": {
          "kubernetes": {
              "usages": [
                  "signing",
                  "key encipherment",
                  "server auth",
                  "client auth"
              ],
              "expiry": "87600h"
          }
      }
  }
}
EOF

# 创建etcd请求文件
echo -e "${green}# 创建etcd请求文件 ${reset}"

ip_list=$(awk '/^\[etcd\]/{flag=1;next}/^\[/{flag=0}flag && NF{print "    \""$0"\","}' /etc/ansible/hosts)

cat > etcd-csr.json <<EOF
{
  "CN": "etcd",
  "hosts": [
$ip_list
    "127.0.0.1"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [{
    "C": "CN",
    "ST": "Beijing",
    "L": "Beijing",
    "O": "kubemsb",
    "OU": "CN"
  }]
}
EOF


# 生成etcd证书
echo -e "${green}生成etcd证书 ${reset}"
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes etcd-csr.json | cfssljson  -bare etcd

# 查看证书
echo -e "${green}查看证书 ${reset}"
ls  | grep etcd



# 下载etcd软件包
echo -e "${green}#etcd下载 ${reset}"
wget http://123.60.152.160/k8s/etcd-v3.5.2-linux-amd64.tar.gz

# 安装etcd软件
echo -e "${green}#安装etcd软件 ${reset}"
tar -xf etcd-v3.5.2-linux-amd64.tar.gz

# 分发etcd软件
echo -e "${green}#安装etcd软件 ${reset}"
ansible etcd -m copy -a "src=./etcd-v3.5.2-linux-amd64/etcd dest=/usr/local/bin/ backup=yes mode=777"
ansible etcd -m copy -a "src=./etcd-v3.5.2-linux-amd64/etcdctl dest=/usr/local/bin/ backup=yes mode=777"
ansible etcd -m copy -a "src=./etcd-v3.5.2-linux-amd64/etcdutl dest=/usr/local/bin/ backup=yes mode=777"

# 主控端创建配置文件
echo -e "${green}#创建 /etc/etcd ${reset}"
mkdir /etc/etcd

# 创建服务配置文件夹
echo -e "${green}#创建服务配置文件夹 ${reset}"
mkdir -p /etc/etcd/ssl
mkdir -p /var/lib/etcd/default.etcd

# 配置文件证书
echo -e "${green}#配置文件证书 ${reset}"
cp ca*.pem /etc/etcd/ssl
cp etcd*.pem /etc/etcd/ssl

# 配置服务文件
echo -e "${green}#配置服务文件 ${reset}"
cat > /etc/systemd/system/etcd.service <<"EOF"
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
EnvironmentFile=-/etc/etcd/etcd.conf
WorkingDirectory=/var/lib/etcd/
ExecStart=/usr/local/bin/etcd \
  --cert-file=/etc/etcd/ssl/etcd.pem \
  --key-file=/etc/etcd/ssl/etcd-key.pem \
  --trusted-ca-file=/etc/etcd/ssl/ca.pem \
  --peer-cert-file=/etc/etcd/ssl/etcd.pem \
  --peer-key-file=/etc/etcd/ssl/etcd-key.pem \
  --peer-trusted-ca-file=/etc/etcd/ssl/ca.pem \
  --peer-client-cert-auth \
  --client-cert-auth
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

## 同步etcd配置到集群其它master节点
echo -e "${red}#同步etcd配置到集群其它master节点 ${reset}"
# 创建目录


ansible etcd -m file -a "path=/etc/etcd state=directory"
ansible etcd -m file -a "path=/etc/etcd/ssl state=directory"
ansible etcd -m file -a "path=/var/lib/etcd/default.etcd state=directory"


ansible etcd -m copy -a "src=/data/k8s-work/ca.pem dest=/etc/etcd/ssl/  backup=yes"
ansible etcd -m copy -a "src=/data/k8s-work/ca-key.pem dest=/etc/etcd/ssl/  backup=yes"
ansible etcd -m copy -a "src=/data/k8s-work/etcd.pem dest=/etc/etcd/ssl/  backup=yes"
ansible etcd -m copy -a "src=/data/k8s-work/etcd-key.pem dest=/etc/etcd/ssl/  backup=yes"


# 服务启动配置文件
ansible etcd -m copy -a "src=/etc/systemd/system/etcd.service dest=/etc/systemd/system  backup=yes mode=660"

# 创建etcd服务配置文件
echo -e "${green}# 创建apiserver服务配置文件... ${reset}"
mkdir /etc/ansible/template
cat > /etc/ansible/template/kube-etcd.conf.j2 <<EOF
#[Member]
ETCD_NAME="etcd-{{ target }}"
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"
ETCD_LISTEN_PEER_URLS="https://{{ target }}:2380"
ETCD_LISTEN_CLIENT_URLS="https://{{ target }}:2379,http://127.0.0.1:2379"

#[Clustering]
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://{{ target }}:2380"
ETCD_ADVERTISE_CLIENT_URLS="https://{{ target }}:2379"
ETCD_INITIAL_CLUSTER="{% for etcd in etcdservers %}etcd-{{ etcd }}=https://{{ etcd }}:2380{% if not loop.last %},{% endif %}{% endfor %} "
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
ETCD_INITIAL_CLUSTER_STATE="new"
EOF

mkdir /etc/ansible/playbook/
cat >  /etc/ansible/playbook/configure-etcd.yaml <<EOF
---
- name: Configure Kubernetes API Server
  hosts: etcd
  tasks:
    - name: Create etced configuration file
      template:
        src: /etc/ansible/template/kube-etcd.conf.j2
        dest: /etc/etcd/etcd.conf
      vars:
        target: "{{ inventory_hostname  }}"
        etcdservers: "{{ groups['etcd'] }}"
EOF


ansible-playbook /etc/ansible/playbook/configure-etcd.yaml


# 重启
ansible etcd -m command -a 'systemctl daemon-reload'
ansible etcd -m command -a 'systemctl enable --now etcd.service'
ansible etcd -m command -a 'systemctl status etcd'


# 处理etcd_endpoints字段
ip_list=$(awk '/^\[etcd\]/{flag=1;next}/^\[/{flag=0}flag && NF' /etc/ansible/hosts)
etcd_endpoints=""

for ip in $ip_list; do
  etcd_endpoints+="https://$ip:2379,"
done

etcd_endpoints=${etcd_endpoints%,} 

ETCDCTL_API=3 /usr/local/bin/etcdctl --write-out=table --cacert=/etc/etcd/ssl/ca.pem --cert=/etc/etcd/ssl/etcd.pem --key=/etc/etcd/ssl/etcd-key.pem --endpoints="$etcd_endpoints" endpoint health

 
# 查看状态
echo -e "${red}# 查看健康状态 ${reset}"
ETCDCTL_API=3 /usr/local/bin/etcdctl --write-out=table --cacert=/etc/etcd/ssl/ca.pem --cert=/etc/etcd/ssl/etcd.pem --key=/etc/etcd/ssl/etcd-key.pem --endpoints="$etcd_endpoints" endpoint health


# 检查ETCD数据库性能
echo -e "${red}# 检查ETCD数据库性能 ${reset}"
ETCDCTL_API=3 /usr/local/bin/etcdctl --write-out=table --cacert=/etc/etcd/ssl/ca.pem --cert=/etc/etcd/ssl/etcd.pem --key=/etc/etcd/ssl/etcd-key.pem --endpoints="$etcd_endpoints" check perf

# 查看谁是leader
echo -e "${red}# 检查ETCD启动状态 ${reset}"
ETCDCTL_API=3 /usr/local/bin/etcdctl --write-out=table --cacert=/etc/etcd/ssl/ca.pem --cert=/etc/etcd/ssl/etcd.pem --key=/etc/etcd/ssl/etcd-key.pem --endpoints="$etcd_endpoints" member list

# 查看整体情况
echo -e "${red}#查看整体情况 ${reset}"
ETCDCTL_API=3 /usr/local/bin/etcdctl --write-out=table --cacert=/etc/etcd/ssl/ca.pem --cert=/etc/etcd/ssl/etcd.pem --key=/etc/etcd/ssl/etcd-key.pem --endpoints="$etcd_endpoints" endpoint status
