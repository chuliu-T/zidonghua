import json
import paramiko

file_path = 'data.json'


# 设置hostname函数
def set_hostname(ssh_client, hostname):
    # 修改主机名并重启
    commands = [
        f"echo {hostname} > /etc/hostname",
        "hostnamectl set-hostname $(cat /etc/hostname)"
    ]
    for command in commands:
        ssh_client.exec_command(command)

# SSH连接函数
def ssh_connect(hostname, ip, password):
    ssh_client = paramiko.SSHClient()
    ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh_client.connect(hostname=ip, username='root', password=password)
        print(f"Connected to {hostname} ({ip}) successfully!")
        return ssh_client
    except paramiko.AuthenticationException:
        print(f"Authentication failed for {hostname} ({ip}).")
        return None

# 读取JSON文件
with open(file_path) as file:
    data = json.load(file)

controller = data["controller"][0]
group1 = data["group1"]

for  host in group1:

    hostname = controller["hostname"]
    ip = controller["ip"]
    passwd = controller["pass"]
# 登录到group2下的主机
    ssh_client = ssh_connect( 'root', ip, passwd)
    if ssh_client:
        try:
            # 连接成功后执行相应命令
            stdin, stdout, stderr = ssh_client.exec_command("hostname")
            set_hostname(ssh_client,hostname)
            print(stdout.read().decode())
        finally:
            ssh_client.close()
