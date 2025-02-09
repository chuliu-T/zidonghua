"""
###########################################################
#   功能：密钥分发
#   date ：2023/7/28
#   writer：tian
###########################################################
"""
import os
import json
import subprocess
import time
import  sys
import paramiko
import pexpect

# 添加段落到文件
def inserttofile(str,file_path):
    pass

# 清理ssh密钥文件
def clean_ssh(ssh_path):
    subprocess.run(['rm' , '-rf', '',ssh_path+'*'])

# 设置用户名
def set_hostname(ssh_client, hostname):
    # 判断主机名是否一样

    # 修改主机名
    commands = [
        f"echo {hostname} > /etc/hostname",
        "hostnamectl set-hostname $(cat /etc/hostname)"
    ]
    for command in commands:
        ssh_client.exec_command(command)

# SSH连接函数
def ssh_connect(remote_user, ip, password,port):
    ssh_client = paramiko.SSHClient()
    ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh_client.connect(hostname=ip, username=remote_user, password=password,port=port)
        print(f"Connected to remote_user:{ remote_user } , ip:{ip} successfully!")
        return ssh_client
    except paramiko.AuthenticationException:
        print(f"Authentication failed for {remote_user} ({ip}).")
        bad_ip.append(ip)
        return False
    except TimeoutError:
        bad_ip.append(ip)
        print('超时~~~')
        return False
    except Exception as err:
        print('ERROR:',err)
        bad_ip.append(ip)
        return False


# 生成密钥
def generate_ssh_keypair():
    if os.path.exists('/key_path'):
        print("SSH keypair already exists.")

    else:
        try:
            # 使用ssh-keygen命令生成SSH密钥对
            child = pexpect.spawn('ssh-keygen -t rsa -b 4096', logfile=sys.stdout, encoding='utf-8')

            while True:
                # 使用expect()函数进行模糊匹配，只要匹配到相应的文本就触发expect()
                index = child.expect(["which to save the key (/root/.ssh/id_rsa):",
                                      "(empty for no passphrase)",
                                      "Enter same passphrase again:",
                                      "Generating public/private rsa key pair.",
                                      "Overwrite (y/n)?",
                                      pexpect.EOF,
                                      pexpect.TIMEOUT], searchwindowsize=-1, timeout=5)
                if index in (0,1,2):
                    child.sendline("\n")
                    continue
                elif index == 3:
                    time.sleep(1)
                    child.sendline("")
                    continue
                elif index == 4:
                    child.sendline("y")
                    continue
                elif index == 5:
                    break
                elif index == 6:
                    print('超时')
                    break


            print("SSH keypair generated successfully.")
        except Exception as e:
            print(f"Error generating SSH keypair: {e}")

# 写入目标主机autu文件
def distribute_ssh_key(ssh_client,pub_key):
    try:
        # 将公钥写入远程主机的~/.ssh/authorized_keys文件
        ssh_cmd = f"cat {ssh_auth_path}"

        stdin, stdout, stderr = ssh_client.exec_command(ssh_cmd)
        remote_auth_file =stdout.read().decode('utf-8').strip()
        print("远程授权文件内容：",remote_auth_file)

        if pub_key in remote_auth_file:
            print("内容已存在于目标文件中，不执行插入操作。")
        else:
            # 插入内容到目标文件
            ssh_cmd = f"mkdir  ~/.ssh/ \n cd ~/.ssh/ \n" \
                   " chattr -ia authorized_keys  \n"\
                  f'echo "{pub_key}" >> {ssh_auth_path}'
            print(ssh_cmd)
            ssh_client.exec_command(ssh_cmd)
            print("内容插入到目标文件成功。")

    except Exception as e:
        print(f"Error distributing SSH public key: {e}")

def key_distribution():
    with open(pub_key_path, 'r') as pub_key_file:
            pub_key = pub_key_file.read()

    print("pub_key :" , pub_key)
    # 分发密钥
    group = str(input("给哪组分配密钥：\n"))
    # 如果为A则选择全部的进行执行
    # if group == 'A' :

    servers = data[group]
    for host in servers:
        hostname = host["hostname"]
        ip = host["ip"]
        passwd = host["pass"]
        port = host["port"]
        # 登录到group2下的主机
        ssh_client = ssh_connect('root', ip, passwd,port)
        if ssh_client:
            try:
                # 连接成功后执行相应命令
                distribute_ssh_key(ssh_client,pub_key)
            finally:
                ssh_client.close()
                # 解决This key is not known by any other names.

                child = pexpect.spawn(f"ssh {remote_username}@{ip}  echo 'verctory'")
                index = child.expect(["ou sure you want to continue connecting (yes/no)?","verctory", pexpect.TIMEOUT],
                                searchwindowsize=-1, timeout=20)
                if index == 0:
                    child.sendline("yes")
                    if child.expect(pexpect.EOF) == 0:
                        print('-' * 50, ip, "第一次录入成功")
                elif index == 1:
                    print(f"SSH public key distributed to {ip} successfully.")
                elif index == 2:
                    print(f"超时~~~~")
                    bad_ip.append(ip)
        else:
            bad_ip.append(ip)
            print(f"链接{ip}错误")
    print(bad_ip)

def command_bash():
    group = str(input("哪组执行命令："))
    command = str(input("执行的命令：",))
    if group not in data.keys():
        group = "default"
    if command == '':
        command = 'echo 正常'
    servers = data[group]
    for host in servers:
        hostname = host["hostname"]
        ip = host["ip"]
        passwd = host["pass"]
        port = host["port"]
        # 登录到group2下的主机
        ssh_client = ssh_connect('root', ip, passwd,port)
        if ssh_client:
            stdin, stdout, stderr = ssh_client.exec_command(command)
            print("执行结果：", stdout.read().decode())
        else:
            bad_ip.append(ip)
            print('执行错误')

    if not bad_ip:
        print('正常执行')
    else:
        print(bad_ip)



if __name__ == '__main__':

    # 指定SSH密钥对的保存路径和文件名
    ssh_path = '/root/.ssh/'
    ssh_key_path = '/root/.ssh/id_rsa'
    pub_key_path = f"{ssh_key_path}.pub"
    ssh_auth_path = ssh_path+"authorized_keys" 


    # 指定要分配密钥的远程主机信息
    remote_username = 'root'
    bad_ip = []

    # 读取JSON文件
    with open('../changeto/data.json') as file:
        data = json.load(file)




    while 1 :
        i = str(input("0：帮助文档\n"
                  "1：生成密钥\n"
                  "2：分发密钥\n"
                  "3：执行命令\n"
                  "4：设置用户名\n"
                  "q：结束程序\n"
                  "请选择功能:\n"))
        if i == '0':
            pass
        elif i == '1':
            generate_ssh_keypair()
        elif i == '2':
            bad_ip.clear()
            key_distribution()
        elif i == '3':
            command_bash()
        elif i == '4':
            pass
        elif i == 'q':
            break
        else:
            print('输入错误')
