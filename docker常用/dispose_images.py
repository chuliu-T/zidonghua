import re

def parse_image_line(line):
    # 使用正则表达式匹配仓库、地址、镜像名称和版本号
    pattern = r'(?P<repo>.+?)\/(?P<address>.+?)\/(?P<name>.+?):(?P<version>.+)'
    pattern = r'^(?:(?P<repo>[^/]+)\/)?(?:(?P<address>[^/]*(?:/[^/]*)*)\/)?(?P<name>[^:]+):(?P<version>.+)$'
    match = re.match(pattern, line)
    if match:
        repo = match.group('repo')
        address = match.group('address')
        name = match.group('name')
        version = match.group('version')
        if address == None:
            if repo == None:
                return (f"{name}", version, name)  # 若仓库和地址都为空，使用镜像名称和版本号作为唯一标识
            else:
                return (f"{repo}/{name}", version,name)
        else:
            return (f"{repo}/{address}/{name}", version,name)
    return None, None

def read_and_process_file(filename):
    unique_images = {}
    
    with open(filename, 'r') as file:
        for line in file:
            line = line.strip()  # 去除行尾的换行符和空格
            image_name, version ,name = parse_image_line(line)
            
            if image_name and version:
                # 使用元组(image_name, version)作为字典的键，避免重复
                unique_images[(image_name, version,name)] = True
    
    # 将字典转换为更易读的列表
    result = [(k[0], k[1] ,k[2]) for k in unique_images.keys()]
    return result


# 调用函数处理文件
result = read_and_process_file('F:\chuliu\work\images-list.txt')
for image_name, version,name in result:
    print(f"docker pull {image_name}:{version}")
for image_name, version,name in result:
    print(f"docker save -o {name}-{version}.tar {image_name}:{version}")
for image_name, version,name in result:
    print(f"docker load -i {name}-{version}.tar")