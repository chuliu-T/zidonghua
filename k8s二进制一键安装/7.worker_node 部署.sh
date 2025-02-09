### 工作节点（worker node）部署 ###

# 工作目录
cd /data/k8s-work/

## Containerd安装及配置 ##

# 获取软件包
wget https://github.com/containerd/containerd/releases/download/v1.6.1/cri-containerd-cni-1.6.1-linux-amd64.tar.gz

# 安装containerd

ansible work -m unarchive -a "src=/data/k8s-work/cri-containerd-cni-1.6.1-linux-amd64.tar.gz dest=/ remote_src=no"


# 生成配置文件并修改

ansible work -m file -a "path=/etc/containerd state=directory"

containerd config default >/etc/containerd/config.toml

ls /etc/containerd/


# 下面的配置文件中已修改，可不执行，仅修改默认时执行。
sed -i 's@systemd_cgroup = false@systemd_cgroup = true@' /etc/containerd/config.toml

# 下面的配置文件中已修改，可不执行，仅修改默认时执行。
sed -i 's@k8s.gcr.io/pause:3.6@registry.aliyuncs.com/google_containers/pause:3.6@' /etc/containerd/config.toml

cat >/etc/containerd/config.toml<<EOF
root = "/var/lib/containerd"
state = "/run/containerd"
oom_score = -999

[grpc]
  address = "/run/containerd/containerd.sock"
  uid = 0
  gid = 0
  max_recv_message_size = 16777216
  max_send_message_size = 16777216

[debug]
  address = ""
  uid = 0
  gid = 0
  level = ""

[metrics]
  address = ""
  grpc_histogram = false

[cgroup]
  path = ""

[plugins]
  [plugins.cgroups]
    no_prometheus = false
  [plugins.cri]
    stream_server_address = "127.0.0.1"
    stream_server_port = "0"
    enable_selinux = false
    sandbox_image = "registry.aliyuncs.com/google_containers/pause:3.6"
    stats_collect_period = 10
    systemd_cgroup = true
    enable_tls_streaming = false
    max_container_log_line_size = 16384
    [plugins.cri.containerd]
      snapshotter = "overlayfs"
      no_pivot = false
      [plugins.cri.containerd.default_runtime]
        runtime_type = "io.containerd.runtime.v1.linux"
        runtime_engine = ""
        runtime_root = ""
      [plugins.cri.containerd.untrusted_workload_runtime]
        runtime_type = ""
        runtime_engine = ""
        runtime_root = ""
    [plugins.cri.cni]
      bin_dir = "/opt/cni/bin"
      conf_dir = "/etc/cni/net.d"
      conf_template = "/etc/cni/net.d/10-default.conf"
    [plugins.cri.registry]
      [plugins.cri.registry.mirrors]
        [plugins.cri.registry.mirrors."docker.io"]
          endpoint = [
            "https://docker.mirrors.ustc.edu.cn",
            "http://hub-mirror.c.163.com"
          ]
        [plugins.cri.registry.mirrors."gcr.io"]
          endpoint = [
            "https://gcr.mirrors.ustc.edu.cn"
          ]
        [plugins.cri.registry.mirrors."k8s.gcr.io"]
          endpoint = [
            "https://gcr.mirrors.ustc.edu.cn/google-containers/"
          ]
        [plugins.cri.registry.mirrors."quay.io"]
          endpoint = [
            "https://quay.mirrors.ustc.edu.cn"
          ]
        [plugins.cri.registry.mirrors."harbor.kubemsb.com"]
          endpoint = [
            "http://harbor.kubemsb.com"
          ]
    [plugins.cri.x509_key_pair_streaming]
      tls_cert_file = ""
      tls_key_file = ""
  [plugins.diff-service]
    default = ["walking"]
  [plugins.linux]
    shim = "containerd-shim"
    runtime = "runc"
    runtime_root = ""
    no_shim = false
    shim_debug = false
  [plugins.opt]
    path = "/opt/containerd"
  [plugins.restart]
    interval = "10s"
  [plugins.scheduler]
    pause_threshold = 0.02
    deletion_threshold = 0
    mutation_threshold = 100
    schedule_delay = "0s"
    startup_delay = "100ms"
EOF

# 安装runc
 

ansible work -m copy -a "src=/etc/containerd/config.toml dest=/etc/containerd/config.toml backup=yes"

 

 

 
wget https://github.com/opencontainers/runc/releases/download/v1.1.0/runc.amd64


chmod +x runc.amd64

# 替换掉原软件包中的runc
ansible work -m copy -a "src=/data/k8s-work/runc.amd64 dest=/usr/local/sbin/runc backup=yes  mode=777"

# mv --force runc.amd64 /usr/local/sbin/runc

ansible work  -a "runc -v"

ansible work  -a "systemctl enable containerd"
ansible work  -a "systemctl start containerd"
ansible work  -a "systemctl status containerd"