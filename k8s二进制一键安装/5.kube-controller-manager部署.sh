#!/bin/bash

red=$(tput setaf 1)  # 红色
green=$(tput setaf 2) # 绿色
reset=$(tput sgr0)   # 颜色重置

# pod ip
pod_ip_range=10.244.0.0 
pod_ip=10.244.0.1
# service ip
service_ip_range=10.96.0.0
service_ip=10.96.0.1

leader=192.168.100.132

# 工作目录
cd /data/k8s-work/

# 创建kubectl证书请求文件
echo -e "${green}# 创建kubectl证书请求文件... ${reset}"
 
cat > admin-csr.json << "EOF"
{
  "CN": "admin",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "Beijing",
      "L": "Beijing",
      "O": "system:masters",             
      "OU": "system"
    }
  ]
}
EOF

# 生成证书文件
echo -e "${green}# 生成证书文件... ${reset}"
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes admin-csr.json | cfssljson -bare admin

# 复制文件到指定目录
# cp admin*.pem /etc/kubernetes/ssl/
echo -e "${green}# 复制文件到指定目录... ${reset}"
ansible master -m copy -a "src=/data/k8s-work/admin-key.pem dest=/etc/kubernetes/ssl/ backup=yes"
ansible master -m copy -a "src=/data/k8s-work/admin.pem dest=/etc/kubernetes/ssl/ backup=yes"


# 生成kubeconfig配置文件
echo -e "${green}# 生成kubeconfig配置文件... ${reset}"
# kube.config 为 kubectl 的配置文件，包含访问 apiserver 的所有信息，如 apiserver 地址、CA 证书和自身使用的证书
 
kubectl config set-cluster kubernetes --certificate-authority=ca.pem --embed-certs=true --server=https://$leader:6443 --kubeconfig=kube.config

kubectl config set-credentials admin --client-certificate=admin.pem --client-key=admin-key.pem --embed-certs=true --kubeconfig=kube.config

kubectl config set-context kubernetes --cluster=kubernetes --user=admin --kubeconfig=kube.config

kubectl config use-context kubernetes --kubeconfig=kube.config

# 准备kubectl配置文件并进行角色绑定
echo -e "${green}# 准备kubectl配置文件并进行角色绑定... ${reset}"
mkdir ~/.kube
cp kube.config ~/.kube/config


# 同步kubectl配置文件到集群其它master节点
echo -e "${green}# 同步kubectl配置文件到集群其它master节点... ${reset}"

ansible master -m file -a "path=/root/.kube state=directory"

ansible master -m copy -a "src=/root/.kube/config dest=/root/.kube/config backup=yes"

kubectl create clusterrolebinding kube-apiserver:kubelet-apis --clusterrole=system:kubelet-api-admin --user kubernetes --kubeconfig=/root/.kube/config

# 查看集群状态
export KUBECONFIG=$HOME/.kube/config

# 查看集群信息
echo -e "${green}# 查看集群信息... ${reset}"
kubectl cluster-info

# 查看集群组件状态
echo -e "${green}# 查看集群组件状态... ${reset}"
kubectl get componentstatuses

# 查看命名空间中资源对象
echo -e "${green}# 查看命名空间中资源对象... ${reset}"
kubectl get all --all-namespaces



# 2.5.6.8 配置kubectl命令补全(可选)
 
yum install -y bash-completion
source /usr/share/bash-completion/bash_completion
source <(kubectl completion bash)
kubectl completion bash > ~/.kube/completion.bash.inc
source '/root/.kube/completion.bash.inc'  
source $HOME/.bash_profile

# 部署kube-controller-manager
# 创建kube-controller-manager证书请求文件

ip_list=$(awk '/^\[master\]/{flag=1;next}/^\[/{flag=0}flag && NF{print "      \""$0"\","}' /etc/ansible/hosts)

echo -e "${green}# 创建kube-controller-manager证书请求文件... ${reset}"
cat > kube-controller-manager-csr.json << EOF
{
    "CN": "system:kube-controller-manager",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "hosts": [
$ip_list
      "127.0.0.1"
    ],
    "names": [
      {
        "C": "CN",
        "ST": "Beijing",
        "L": "Beijing",
        "O": "system:kube-controller-manager",
        "OU": "system"
      }
    ]
}
EOF

# 说明：

# hosts 列表包含所有 kube-controller-manager 节点 IP；
# CN 为 system:kube-controller-manager;
# O 为 system:kube-controller-manager，kubernetes 内置的 ClusterRoleBindings system:kube-controller-manager 赋予 kube-controller-manager 工作所需的权限

# 创建kube-controller-manager证书文件
echo -e "${green}# 创建kube-controller-manager证书文件... ${reset}"
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager

# 查看生成的证书
echo -e "${green}# 查看生成的证书... ${reset}"
ls | grep manager


# 创建kube-controller-manager的kube-controller-manager.kubeconfig
echo -e "${green}# 创建kube-controller-manager的kube-controller-manager.kubeconfig... ${reset}"
kubectl config set-cluster kubernetes --certificate-authority=ca.pem --embed-certs=true --server=https://$leader:6443 --kubeconfig=kube-controller-manager.kubeconfig

kubectl config set-credentials system:kube-controller-manager --client-certificate=kube-controller-manager.pem --client-key=kube-controller-manager-key.pem --embed-certs=true --kubeconfig=kube-controller-manager.kubeconfig

kubectl config set-context system:kube-controller-manager --cluster=kubernetes --user=system:kube-controller-manager --kubeconfig=kube-controller-manager.kubeconfig

kubectl config use-context system:kube-controller-manager --kubeconfig=kube-controller-manager.kubeconfig

# 创建kube-controller-manager配置文件
echo -e "${green}# 创建kube-controller-manager配置文件... ${reset}"
cat > kube-controller-manager.conf << EOF
KUBE_CONTROLLER_MANAGER_OPTS="--port=10252 \
  --secure-port=10257 \
  --bind-address=127.0.0.1 \
  --kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \
  --service-cluster-ip-range=$service_ip_range/16 \
  --cluster-name=kubernetes \
  --cluster-signing-cert-file=/etc/kubernetes/ssl/ca.pem \
  --cluster-signing-key-file=/etc/kubernetes/ssl/ca-key.pem \
  --allocate-node-cidrs=true \
  --cluster-cidr=$pod_ip_range/16 \
  --experimental-cluster-signing-duration=87600h \
  --root-ca-file=/etc/kubernetes/ssl/ca.pem \
  --service-account-private-key-file=/etc/kubernetes/ssl/ca-key.pem \
  --leader-elect=true \
  --feature-gates=RotateKubeletServerCertificate=true \
  --controllers=*,bootstrapsigner,tokencleaner \
  --horizontal-pod-autoscaler-use-rest-clients=true \
  --horizontal-pod-autoscaler-sync-period=10s \
  --tls-cert-file=/etc/kubernetes/ssl/kube-controller-manager.pem \
  --tls-private-key-file=/etc/kubernetes/ssl/kube-controller-manager-key.pem \
  --use-service-account-credentials=true \
  --alsologtostderr=true \
  --logtostderr=false \
  --log-dir=/var/log/kubernetes \
  --v=2"
EOF

# 创建服务启动文件
echo -e "${green}# 创建服务启动文件... ${reset}"
cat > kube-controller-manager.service << "EOF"
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-/etc/kubernetes/kube-controller-manager.conf
ExecStart=/usr/local/bin/kube-controller-manager $KUBE_CONTROLLER_MANAGER_OPTS
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 同步文件到集群master节点
echo -e "${green}# 同步文件到集群master节点... ${reset}"
ansible master -m copy -a "src=/data/k8s-work/kube-controller-manager-key.pem  dest=/etc/kubernetes/ssl/ backup=yes"
ansible master -m copy -a "src=/data/k8s-work/kube-controller-manager.pem  dest=/etc/kubernetes/ssl/ backup=yes"

ansible master -m copy -a "src=/data/k8s-work/kube-controller-manager.kubeconfig dest=/etc/kubernetes/ backup=yes"
ansible master -m copy -a "src=/data/k8s-work/kube-controller-manager.conf dest=/etc/kubernetes/ backup=yes"
ansible master -m copy -a "src=/data/k8s-work/kube-controller-manager.service dest=/usr/lib/systemd/system/ backup=yes"


#查看证书
echo -e "${green}# 查看证书... ${reset}"
 

# 启动服务
echo -e "${green}# 启动服务... ${reset}"
ansible master  -a "systemctl daemon-reload "
ansible master  -a "systemctl enable --now kube-controller-manager"
ansible master  -a "systemctl status kube-controller-manager"
ansible master  -a "kubectl get componentstatuses"