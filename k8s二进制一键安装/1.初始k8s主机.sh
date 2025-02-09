###########################################################
#   功能：K8S 环境初始化
#   date ：2023/4/13
#   writer：tian
###########################################################

currunttime=`date "+%F" `
# 基本配置
# 配置 映射与hostname
ip_dev=`ip a | grep '2: ' | awk -F ': ' '{print $2}'`

network_path=/etc/sysconfig/network-scripts/ifcfg-${ip_dev}

ip=`ip a | grep $ip_dev | grep scope | awk '{print $2}'|awk -F '/' '{print $1}'`

DNS="223.5.5.5"

cat > ./host <<EOF
192.168.100.132 master
192.168.100.133 node1
192.168.100.134 node2
EOF

input_file="./host"
content=$(cat $input_file)

# 将内容写入到特定文件中
output_file="/etc/hosts"
# 检查输出文件中是否存在相同的行
while read line; do
  if grep -Fxq "$line" "$output_file"; then
    echo "输出文件中已经存在相同的行，无需写入。"
  else
    echo "$line" >> $output_file
    echo "内容已经成功写入到 $output_file 文件中。"
  fi
done <<< "$content"

# 配置主机映射
function set_Hosts(){
output_file="/etc/hosts"
content=$(cat $output_file)

  # host配置
while read i; do
        if [[ `echo $i | awk '{print $1}'` == $ip ]];
        then
                echo $i
                echo $i | awk '{print $2}'
                hostnamectl  set-hostname  `echo $i | awk '{print $2}'`
        fi
done <<< "$content"
}
set_Hosts


# IP改为静态
function set_network_static(){
    local item="Set the ip address to static"

  if [ `grep  'BOOTPROTO' $network_path | awk -F= '{print $2}'` == "static" ];
  then
          echo -e "\033[1;31;40mThe BOOTPROTO of network is static\033[0m"
  else
          sed -ri.{$currunttime} 's#BOOTPROTO(.*)#BOOTPROTO=static#g' $network_path
          sed -ri 's#ONBOOT(.*)#ONBOOT=yes#g' $network_path
          cat <<EOF>> $network_path
IPADDR=$ip
GATEWAY=`ip route show | grep via | grep default | awk '{print $3}'`
NETMASK=255.255.255.0
DNS1=$DNS
EOF
          systemctl restart network
  fi
}
set_network_static



#-----------------------------------------------------------------------------------
# 配置yum源
yum -y install wget
# 备份
mkdir -p /bak/repo
mv /etc/yum.repos.d/* /bak/repo 

# 基本yum源
wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo   >/dev/null
yum clean all >/dev/null
yum makecache >/dev/null

#  Yum源工具的安装
sudo yum install -y yum-utils  >/dev/null 

# epel源
sudo yum-config-manager \
              --add-repo \
              https://mirrors.aliyun.com/repo/epel-7.repo >/dev/null 

yum clean all
yum makecache 
#-----------------------------------------------------------------------------------



#-----------------------------------------------------------------------------------
# 软件安装
yum install  jq psmisc vim net-tools telnet yum-utils device-mapper-persistent-data lvm2 git lrzsz -y  >/dev/null 

# python 依赖环境
yum -y install zlib-devel bzip2-devel openssl-devel ncurses-devel sqlite-devel readline-devel tk-devel gcc make  >/dev/null 
#-----------------------------------------------------------------------------------


#-----------------------------------------------------------------------------------
######### 防火墙 selinux  内存 ###########################################
# 查看防火墙状态
firewall-cmd --state
# 临时停止防火墙
systemctl stop firewalld.service
# 禁止防火墙开机启动
systemctl disable firewalld.service
# 查看防火墙状态
firewall-cmd --state


# 查看selinux状态
getenforce
# 临时关闭selinux
setenforce 0
# 永久关闭selinux
sed -i 's/^ *SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
# 查看状态
sestatus

# 临时关闭swap
swapoff -a
# 永久关闭swap
sed -i.bak '/swap/s/^/#/' /etc/fstab
# 修改内核参数
echo 'vm.swappiness=0' >>  /etc/sysctl.conf
# 重新加载参数 -p   从指定的文件加载系统参数，如不指定即从/etc/sysctl.conf中加载
sysctl -p

# 定时统一时间
yum install -y ntp
cat >> /etc/crontab <<EOF
*/1  *  *  *  * root ntpdate time1.aliyun.com >>/root/log 2>/dev/null
EOF
systemctl restart ntpd
systemctl enabled ntpd
#-----------------------------------------------------------------------------------




# 系统优化-------------------------------------------------------------------

ulimt -SHn 65536

cp /etc/security/limits.conf /etc/security/limits.conf.${current_time} && \
echo "*           soft    nofile          100000
*           hard    nofile          100000
*           soft    nproc           65535
*           hard    nproc           65535
*           soft    core            unlimited
*           hard    core            unlimited" > /etc/security/limits.conf

# 安装 ipvs 管理工具及模块加载

yum -y install ipvsadm ipset sysstat conntrack libseccomp

# 临时生效
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack
# 内核4.19 为modprobe -- nf_conntrack  以下为：nf_conntrack_ipv4 


# 永久生效

cat >/etc/modules-load.d/ipvs.conf <<EOF
ip_vs
ip_vs_lc
ip_vs_wlc
ip_vs_rr
ip_vs_wrr
ip_vs_lblc
ip_vs_lblcr
ip_vs_dh
ip_vs_sh
ip_vs_fo
ip_vs_nq
ip_vs_sed
ip_vs_ftp
ip_vs_sh
nf_conntrack
ip_tables
ip_set
xt_set
ipt_set
ipt_rpfilter
ipt_REJECT
ipip
EOF
#-----------------------------------------------------------------------------------


#-----------------------------------------------------------------------------------
# 加载containerd 相关内核模块
# 临时生效
modprobe overlay
modprobe br_netfilter


# 永久生效
cat <<EOF> /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

# 设置开机自启
systemctl enable --now systemd-modules-load.service
#-----------------------------------------------------------------------------------


#-----------------------------------------------------------------------------------
# 内核优化------------------------------------------------
cat <<EOF > /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
fs.may_detach_mounts = 1
vm.overcommit_memory=1
vm.panic_on_oom=0
fs.inotify.max_user_watches=89100
fs.file-max=52706963
fs.nr_open=52706963
net.netfilter.nf_conntrack_max=2310720

net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl =15
net.ipv4.tcp_max_tw_buckets = 36000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_orphans = 327680
net.ipv4.tcp_orphan_retries = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.ip_conntrack_max = 131072
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_timestamps = 0
net.core.somaxconn = 16384
EOF

# 应用 sysctl 参数而无需重新启动
sudo sysctl --system


# 所有节点配置完内核后，重启服务器，保证重启后内核依旧加载
# reboot -h now

# 重启后查看ipvs模块加载情况：
lsmod | grep --color=auto -e ip_vs -e nf_conntrack

# 重启后查看containerd相关模块加载情况：
lsmod | egrep -e 'br_netfilter' -e 'overlay'
#-----------------------------------------------------------------------------------


