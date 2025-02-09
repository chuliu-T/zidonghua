import json
import csv

file_path = 'IP.csv'

# 用于存储读取到的数据
data_dict = {}

ip_hostnames = []


# 读取CSV文件
with open(file_path, newline='' ,encoding='utf-8') as csvfile:
    csv_reader = csv.DictReader(csvfile)
    for row in csv_reader:
        # hosts文件
        ip = row['ip']
        hostname = row['hostname']

        # 判断是否重复
        if (ip, hostname) not in ip_hostnames:
            ip_hostnames.append((ip, hostname))

        # json
        group = row['group']
        ip_info = {
            'ip': row['ip'],
            'hostname': row['hostname'],
            'pass': row['pass'],
            'port':row['port']
        }

        if group in data_dict:
            members = data_dict[group]
            members_ips = [member["ip"] for member in members]
            if ip_info["ip"] not in members_ips:
                data_dict[group].append(ip_info)
            else:print('重复添加:',ip_info["ip"])
        else:
            data_dict[group] = [ip_info]

with open('data.json', 'w') as file:
    json.dump(data_dict,file,indent=2)


with open('hosts', 'a+') as hosts_file:
    existing_lines = hosts_file.readlines()

# 将读取到的ip和hostname信息写入/etc/hosts文件
with open('hosts', 'a+') as hosts_file:
    for ip, hostname in ip_hostnames:
        line = f'{ip}\t{hostname}\n'
        # 判断是否已存在重复行
        if line not in existing_lines:
            hosts_file.write(line)

