import psutil
import subprocess
import uuid
import cpuinfo
import re
import pymysql
import configparser
# 获取MAC地址
def get_mac_address():
    mac
    return mac


# 获取内存信息
def get_memory_info():
    memory_info = psutil.virtual_memory()
    return round((memory_info.total/(1024**3)))

# 获取硬盘信息
def get_disk_info():
    # 运行WMIC命令获取硬盘信息
    cmd = 'wmic diskdrive get size,model'
    result = subprocess.check_output(cmd, shell=True).decode()

    # 解析结果
    drives = {}
    for line in result.split('\n'):
        match = re.search(r'(.*)\s+(\d+)', line.strip())
        if match:
            model, size = match.groups()
            drives[model] = int(size)
    # Formatting the result as a string
    drive_info = "\n".join([f"Model: {model}, Size: {size / (1024 ** 3):.2f} GB" for model, size in drives.items()])
    return drive_info
# 获取硬盘序列号
def get_disk_serial_number():
    result = subprocess.check_output(['wmic', 'diskdrive', 'get', 'SerialNumber'])
    lines = result.decode()

    # 找到第一个换行符(\n)的位置
    first_newline_pos = lines.find('\n')

    # 找到紧随其后的回车符(\r)的位置
    next_carriage_pos = lines.find('\r', first_newline_pos)

    # 提取两个符号之间的内容，并去除首尾的空格
    extracted_data = lines[first_newline_pos:next_carriage_pos].strip()
    return extracted_data

# 获取出厂序列号
def get_manufacturer_serial_number():
    result = subprocess.check_output('wmic bios get serialnumber').decode('utf-8').strip().split('\n')[1]
    return result

if __name__ == '__main__':
    print('get_mac_address')
    mac_address = ':'.join(['{:02x}'.format((uuid.getnode() >> elements) & 0xff) for elements in range(5, -1, -1)])
    print('cpu_info')
    cpu_info =  cpuinfo.get_cpu_info()['brand_raw']
    print('memory_info')
    memory_info = get_memory_info()
    print('disk_info')
    disk_info = get_disk_info()
    print('disk_serial_number')
    disk_serial_number = get_disk_serial_number()
    print('manufacturer_serial_number')
    manufacturer_serial_number = get_manufacturer_serial_number()

    info_string = f"MAC地址: {mac_address}\nCPU信息: {cpu_info}\n内存信息: {memory_info} GB\n硬盘信息: {disk_info}\n硬盘序列号: {disk_serial_number}\n出厂序列号: {manufacturer_serial_number}"

    print(info_string)

    # 连接到MySQL数据库
    connection = pymysql.connect(
        host='123.60.152.160',
        user='sql',
        password='Mysql#0011',
        database='maintenance'
    )

    # 创建一个MySQL游标对象
    cursor = connection.cursor()

    config = configparser.ConfigParser()
    config.read('config.ini')
    name = config.get('General', 'name')
    # 将信息插入到数据库中
    try:
        cursor.execute("INSERT INTO person_info (name,information) VALUES (%s,%s)", (name, info_string,))
        connection.commit()
        print("信息成功插入到数据库中")
    except Exception as e:
        print(f"插入数据库时发生错误: {e}")
        connection.rollback()
    finally:
        # 关闭数据库连接
        connection.close()