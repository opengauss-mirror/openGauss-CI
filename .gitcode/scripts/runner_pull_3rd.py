#!/usr/bin/env python3
"""
更新opengauss的三方库到k8s资源池门禁共享路径下

按需触发
"""
import sys
from pathlib import Path
import subprocess

def main():
    
    print("------------ df -h -------------")
    cmd1 = "df -h"
    s, o = subprocess.getstatusoutput(cmd1)
    print(o)

    print("------------ ls -------------")
    cmd2 = "ls /opengauss_3rd_download"
    s, o = subprocess.getstatusoutput(cmd2)
    print(o)


    print("------------ touch -------------")
    cmd3 = "touch /opengauss_3rd_download/testfile-20261028"
    s, o = subprocess.getstatusoutput(cmd3)
    print(o)

    print('--------------- end -------------')

if __name__ == "__main__":
    main()
