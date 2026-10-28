#!/usr/bin/env python3
"""
更新opengauss的三方库到k8s资源池门禁共享路径下
"""
import sys
from pathlib import Path
import subprocess

def main():
    
    cmd1 = "df -h"
    s, o = subprocess.getstatusoutput(cmd1)
    print(o)

    cmd2 = "touch /opengauss_3rd_download/testfile-2026-10-28-16-00"
    s, o = subprocess.getstatusoutput(cmd2)
    print(o)

if __name__ == "__main__":
    main()
