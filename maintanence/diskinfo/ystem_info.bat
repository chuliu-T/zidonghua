@echo off
echo 获取系统信息
echo -----------------------------------

echo MAC地址:
getmac

echo.
echo CPU信息:
wmic cpu get name

echo.
echo 内存信息:
wmic MEMORYCHIP get Capacity

echo.
echo 硬盘信息:
wmic diskdrive get size,model

echo.
echo 硬盘序列号:
wmic diskdrive get SerialNumber

echo.
echo 出厂序列号:
wmic bios get serialnumber

echo.
echo 所有信息已显示完毕
pause
