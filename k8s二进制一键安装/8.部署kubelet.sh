# 部署kubelet
# 在master1上操作
# 工作目录
# 环境变量

clusterDNS=10.96.0.2


# service ip
service_ip_range=10.96.0.0
service_ip=10.96.0.1

leader=192.168.100.132


cd /data/k8s-work/

# 创建kubelet-bootstrap.kubeconfig
 
BOOTSTRAP_TOKEN=$(awk -F "," '{print $1}' /etc/kubernetes/token.csv)

kubectl config set-cluster kubernetes --certificate-authority=ca.pem --embed-certs=true --server=https://$leader:6443 --kubeconfig=kubelet-bootstrap.kubeconfig

kubectl config set-credentials kubelet-bootstrap --token=${BOOTSTRAP_TOKEN} --kubeconfig=kubelet-bootstrap.kubeconfig

kubectl config set-context default --cluster=kubernetes --user=kubelet-bootstrap --kubeconfig=kubelet-bootstrap.kubeconfig

kubectl config use-context default --kubeconfig=kubelet-bootstrap.kubeconfig

kubectl create clusterrolebinding cluster-system-anonymous --clusterrole=cluster-admin --user=kubelet-bootstrap

kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --user=kubelet-bootstrap --kubeconfig=kubelet-bootstrap.kubeconfig

kubectl describe clusterrolebinding cluster-system-anonymous

kubectl describe clusterrolebinding kubelet-bootstrap

#  创建kubelet配置文件
 

 

cat > /etc/ansible/template/kube-kubelet.json.j2 <<EOF
{
  "kind": "KubeletConfiguration",
  "apiVersion": "kubelet.config.k8s.io/v1beta1",
  "authentication": {
    "x509": {
      "clientCAFile": "/etc/kubernetes/ssl/ca.pem"
    },
    "webhook": {
      "enabled": true,
      "cacheTTL": "2m0s"
    },
    "anonymous": {
      "enabled": false
    }
  },
  "authorization": {
    "mode": "Webhook",
    "webhook": {
      "cacheAuthorizedTTL": "5m0s",
      "cacheUnauthorizedTTL": "30s"
    }
  },
  "address": "{{ target }}",
  "port": 10250,
  "readOnlyPort": 10255,
  "cgroupDriver": "systemd",                    
  "hairpinMode": "promiscuous-bridge",
  "serializeImagePulls": false,
  "clusterDomain": "cluster.local.",
  "clusterDNS": ["${clusterDNS}"]
}
EOF

cat >  /etc/ansible/playbook/configure-kubelet.json.yaml <<EOF
---
- name: Configure kubelet.json
  hosts: all
  tasks:
    - name: Create kubelet service configuration file kubelet.json
      template:
        src: /etc/ansible/template/kube-kubelet.json.j2
        dest: /etc/kubernetes/kubelet.json
      vars:
        target: "{{ inventory_hostname  }}"
EOF


ansible-playbook /etc/ansible/playbook/configure-kubelet.json.yaml



# 创建kubelet服务启动管理文件
 
cat > kubelet.service << "EOF"
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
WorkingDirectory=/var/lib/kubelet
ExecStart=/usr/local/bin/kubelet \
  --bootstrap-kubeconfig=/etc/kubernetes/kubelet-bootstrap.kubeconfig \
  --cert-dir=/etc/kubernetes/ssl \
  --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \
  --config=/etc/kubernetes/kubelet.json \
  --cni-bin-dir=/opt/cni/bin \
  --cni-conf-dir=/etc/cni/net.d \
  --container-runtime=remote \
  --container-runtime-endpoint=unix:///run/containerd/containerd.sock \
  --network-plugin=cni \
  --rotate-certificates \
  --pod-infra-container-image=registry.aliyuncs.com/google_containers/pause:3.2 \
  --root-dir=/etc/cni/net.d \
  --alsologtostderr=true \
  --logtostderr=false \
  --log-dir=/var/log/kubernetes \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF


# 同步文件到集群节点
 
ansible all -m copy -a "src=/data/k8s-work/kubelet-bootstrap.kubeconfig dest=/etc/kubernetes/  backup=yes"
# ansible all -m copy -a "src=/data/k8s-work/kubelet.json dest=/etc/kubernetes/ backup=yes"
ansible all -m copy -a "src=/data/k8s-work/ca.pem dest=/etc/kubernetes/ssl/ backup=yes"
ansible all -m copy -a "src=/data/k8s-work/kubelet.service dest=/usr/lib/systemd/system/ backup=yes"



# 说明：
# kubelet.json中address需要修改为当前主机IP地址。

# 2.5.9.2.5 创建目录及启动服务

ansible all -m file -a "path=/var/lib/kubelet state=directory"
ansible all -m file -a "path=/var/log/kubernetes state=directory"


ansible work  -a "systemctl daemon-reload"
ansible work  -a "systemctl enable --now kubelet"
ansible work  -a "systemctl status kubelet"


kubectl get nodes

kubectl get csr

## 部署kube-proxy
 
# 创建kube-proxy证书请求文件
 
cat > kube-proxy-csr.json << "EOF"
{
  "CN": "system:kube-proxy",
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

# 生成证书
 
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-proxy-csr.json | cfssljson -bare kube-proxy

ls kube-proxy*


# 创建kubeconfig文件
 
kubectl config set-cluster kubernetes --certificate-authority=ca.pem --embed-certs=true --server=https://$leader:6443 --kubeconfig=kube-proxy.kubeconfig

kubectl config set-credentials kube-proxy --client-certificate=kube-proxy.pem --client-key=kube-proxy-key.pem --embed-certs=true --kubeconfig=kube-proxy.kubeconfig

kubectl config set-context default --cluster=kubernetes --user=kube-proxy --kubeconfig=kube-proxy.kubeconfig

kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig

# 创建服务配置文件
 


cat > /etc/ansible/template/kube-proxy.yaml.j2 <<EOF
apiVersion: kubeproxy.config.k8s.io/v1alpha1
bindAddress: {{ target }}
clientConnection:
  kubeconfig: /etc/kubernetes/kube-proxy.kubeconfig
clusterCIDR: $service_ip_range/16
healthzBindAddress: {{ target }}:10256
kind: KubeProxyConfiguration
metricsBindAddress: {{ target }}:10249
mode: "ipvs"
EOF


cat >  /etc/ansible/playbook/configure-kube-proxy.yaml <<EOF
---
- name: Configure kube-proxy.yaml
  hosts: work
  tasks:
    - name: Create kubelet service configuration file kube-proxy.yaml
      template:
        src: /etc/ansible/template/kube-proxy.yaml.j2
        dest: /etc/kubernetes/kube-proxy.yaml
      vars:
        target: "{{ inventory_hostname  }}"
EOF


ansible-playbook /etc/ansible/playbook/configure-kube-proxy.yaml



# 创建服务启动管理文件
 
cat >  kube-proxy.service << "EOF"
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/kubernetes/kubernetes
After=network.target

[Service]
WorkingDirectory=/var/lib/kube-proxy
ExecStart=/usr/local/bin/kube-proxy \
  --config=/etc/kubernetes/kube-proxy.yaml \
  --alsologtostderr=true \
  --logtostderr=false \
  --log-dir=/var/log/kubernetes \
  --v=2
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# 同步文件到集群工作节点主机
 
ansible work -m copy -a "src=/data/k8s-work/kube-proxy-key.pem dest=/etc/kubernetes/ssl/   backup=yes"
ansible work -m copy -a "src=/data/k8s-work/kube-proxy.pem dest=/etc/kubernetes/ssl/   backup=yes"
ansible work -m copy -a "src=/data/k8s-work/kube-proxy.kubeconfig dest=/etc/kubernetes/  backup=yes"
# ansible work -m copy -a "src=/data/k8s-work/kube-proxy.yaml dest=/etc/kubernetes/  backup=yes" -------------上边的剧本已经实现
ansible work -m copy -a "src=/data/k8s-work/kube-proxy.service dest=/usr/lib/systemd/system/ backup=yes"


# 说明：
# 修改kube-proxy.yaml中IP地址为当前主机IP.

# 2.5.9.3.7 服务启动
 
# mkdir -p /var/lib/kube-proxy"
ansible work -m file -a "path=/var/lib/kube-proxy state=directory"

ansible work  -a "systemctl daemon-reload"
ansible work  -a "systemctl enable --now kube-proxy"
ansible work  -a "systemctl status kube-proxy"