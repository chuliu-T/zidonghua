import  paramiko

ssh_path = '/root/.ssh/'
ssh_key_path = '/root/.ssh/id_rsa'
pub_key_path = f"{ssh_key_path}.pub"
ssh_auth_path = ssh_path+"authorized_keys"
ssh_cmd = f"cat {ssh_auth_path}"
ssh_client = paramiko.SSHClient()
ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

ssh_client.connect(hostname= '192.168.100.3', username='root', password='123')

if ssh_client:
    stdin, stdout, stderr = ssh_client.exec_command(ssh_cmd)
    print("执行结果：", stdout.read().decode())
else:
    print('执行错误')