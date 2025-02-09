import pexpect
import subprocess

def distribute_ssh_key(ssh_client,pub_key_path):
    try:
        # 读取公钥文件
        with open(pub_key_path, 'r') as pub_key_file:
            pub_key = pub_key_file.read().strip()

        # 将公钥写入远程主机的~/.ssh/authorized_keys文件
        ssh_cmd = f"echo '{pub_key}' >> ~/.ssh/authorized_keys"

        ssh_client.exec_command("hostname")

        # 使用pexpect自动输入密码
        child = pexpect.spawn(f"ssh {remote_username}@{remote_host} {ssh_cmd}")

        child.expect(" you sure you want to continue connecting (yes/no)?")
        child.sendline('yes')
        child.expect(pexpect.EOF)
        print(f"SSH public key distributed to {remote_host} successfully.")
    except Exception as e:
        print(f"Error distributing SSH public key: {e}")

def distribute_ssh_key(pub_key_path, remote_host, remote_username):
    try:
        # 读取公钥文件
        with open(pub_key_path, 'r') as pub_key_file:
            pub_key = pub_key_file.read().strip()

        # 将公钥写入远程主机的~/.ssh/authorized_keys文件
        ssh_cmd = f"echo '{pub_key}' >> ~/.ssh/authorized_keys"
        subprocess.run(['ssh', f'{remote_username}@{remote_host}', ssh_cmd])
        print(f"SSH public key distributed to {remote_host} successfully.")
    except Exception as e:
        print(f"Error distributing SSH public key: {e}")