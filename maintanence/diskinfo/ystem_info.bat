@echo off
echo ��ȡϵͳ��Ϣ
echo -----------------------------------

echo MAC��ַ:
getmac

echo.
echo CPU��Ϣ:
wmic cpu get name

echo.
echo �ڴ���Ϣ:
wmic MEMORYCHIP get Capacity

echo.
echo Ӳ����Ϣ:
wmic diskdrive get size,model

echo.
echo Ӳ�����к�:
wmic diskdrive get SerialNumber

echo.
echo �������к�:
wmic bios get serialnumber

echo.
echo ������Ϣ����ʾ���
pause
