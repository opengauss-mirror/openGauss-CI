#
# Copyright (c) Huawei Technologies CO., Ltd. 2022-2026. All rights reserved.
#
import datetime
import json
import sys
import time
import argparse
import requests
import subprocess

# 【关键】必须引入 APIG SDK 进行标准签名
try:
    from apig_sdk import signer
except ImportError:
    print("Error: apig_sdk not found. Please install it via 'pip install apig-sdk' or check your python environment.")
    sys.exit(1)

class CodeCheck(object):

    def __init__(self, scan_ak, scan_sk, result_ak, result_sk, access_token,state_file,result_file, pr_id, repository_name,
                 codecheck_ip='https://apig.openlibing.com/openlibing-codecheck',
                 gitcode_api='https://api.gitcode.com/api/v5/repos',
                 codecheck_prefix='/ci-portal/webhook/codecheck/v1'):
        self.pr_url = None
        self.task_id = None
        self.uuid = None
        self.result = None
        self.report_url = None
        self.action_type = None

        # 四把钥匙：扫描用一对，查询用一对
        self.scan_ak = scan_ak
        self.scan_sk = scan_sk
        self.result_ak = result_ak
        self.result_sk = result_sk

        self.access_token = access_token
        self.pr_id = pr_id
        self.repository_name = repository_name
        self.codecheck_ip = codecheck_ip
        self.gitcode_api = gitcode_api
        self.codecheck_prefix = codecheck_prefix
        self.gitcode_domian = "https://gitcode.com/opengauss"
        self.state_file = state_file
        self.result_file = result_file

    def _get_pr_url(self):
        self.pr_url = f"{self.gitcode_domian}/{self.repository_name}/merge_requests/{self.pr_id}"
        print(f"pr_url: {self.pr_url}")

    def _get_create_task(self):
        """
        使用 [Scan AK/SK] + [APIG 标准 SDK] 进行签名 (创建任务)
        """
        try:
            # 注意：这里 codecheck_ip 可能已经包含了域名，拼接时需注意不要重复
            # 如果 codecheck_ip 是 'https://www.openlibing.com'，prefix 是 '/ci-portal/...'
            # 则 task_url = 'https://www.openlibing.com/ci-portal/...'
            task_url = f'{self.codecheck_ip}{self.codecheck_prefix}/task'

            params = {
                "pr_url": self.pr_url,
                "projectName": "opengauss"
            }
            body = json.dumps(params)

            method = 'POST'
            headers = {"Content-Type": "application/json"}

            # --- 核心：使用扫描密钥签名 ---
            request = signer.HttpRequest(method, task_url, headers, body)
            sig = signer.Signer()
            sig.Key = self.scan_ak      # 使用扫描 AK
            sig.Secret = self.scan_sk   # 使用扫描 SK
            sig.Sign(request)
            # ----------------------------------

            print(f"[Create Task] URL: {task_url}")

            responsetemp = requests.request(
                request.method,
                request.scheme + "://" + request.host + request.uri,
                headers=request.headers,
                data=request.body
            )

            print(f"[Create Task] 响应状态码: {responsetemp.status_code}")
            # 调试时可开启下方打印
            # print(f"[Create Task] 响应内容: {responsetemp.text}")

            try:
                response = responsetemp.json()
            except ValueError as e:
                print("无法解析 JSON 响应")
                print(f'[code check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] 无法解析 JSON 响应 \n[{e}]')
                return

            # 注意：原代码中 code 是字符串 '200'
            if str(response.get('code')) == '200':
                self.uuid = response.get('uuid')
                self.task_id = response.get('task_id')
                print(f'[code check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] create task success (uuid: {self.uuid})')
            else:
                print(f'[code check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] create task failed '
                      f'\n[{response.get("msg")}]')
        except Exception as e:
            print(f'[code check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] create task error \n[{e}]')

    def _get_task_result(self):
        """
        使用 [Result AK/SK] + [APIG 标准 SDK] 进行签名 (查询结果)
        """
        expire_time = 0
        while expire_time < 1800:
            time.sleep(10)
            try:
                status_url = f'{self.codecheck_ip}{self.codecheck_prefix}/task/status'
                params = {
                    "uuid": self.uuid,
                    "task_id": self.task_id
                }
                body = json.dumps(params)

                method = 'POST'
                headers = {"Content-Type": "application/json"}

                # --- 核心：使用查询密钥签名 ---
                request = signer.HttpRequest(method, status_url, headers, body)
                sig = signer.Signer()
                sig.Key = self.result_ak      # 使用查询 AK
                sig.Secret = self.result_sk   # 使用查询 SK
                sig.Sign(request)
                # ----------------------------------

                print(f"[Query Result] URL: {status_url}")

                responsetemp = requests.request(
                    request.method,
                    request.scheme + "://" + request.host + request.uri,
                    headers=request.headers,
                    data=request.body
                )

                print(f"[Query Result] 响应状态码: {responsetemp.status_code}")
                # 调试时可开启下方打印
                # print(f"[Query Result] 响应内容: {responsetemp.text}")

                response = responsetemp.json()
                resp_code = str(response.get('code'))

                if resp_code == '200':
                    self.result = response.get('state')
                    self.report_url = response.get('data')
                    print(f'[code check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] task success')
                    break
                elif resp_code == '100':
                    print(f'[code check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] task running')
                    expire_time = expire_time + 10
                    continue
                elif resp_code == '401':
                    print(f'[code check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] no permission (401)')
                    break
                else:
                    print(f'[code check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] task failed '
                          f'\n[{response.get("msg")}]')
                    break
            except Exception as e:
                print(f'[code check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] task error \n[{e}]')
                break

    def run(self):
        # 1. 获取 PR URL
        self._get_pr_url()
        if not self.pr_url:
            print(f'[code check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] Error: pr_url is null')
            sys.exit(-1)

        # 2. 创建门禁检查任务
        self._get_create_task()
        if not self.uuid or not self.task_id:
            print(f'[code check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] create codecheck task error: missing uuid or task_id')
            sys.exit(-1)

        # 3. 获取门禁检查任务结果
        self._get_task_result()

        if not self.report_url:
            print(f'[code check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] Error: report_url is null')
            sys.exit(-1)

        
        with open(self.result_file, "w", encoding="utf-8") as f:
            f.write(self.report_url)
            

        # 检查结果不为 pass 表示提交代码存在 cleancode 问题
        if self.result != "pass":
            print(f'[code check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] Access control check failed')
            with open(self.state_file, "w", encoding="utf-8") as f:
                f.write("failed")
            sys.exit(-1)
        with open(self.state_file, "w", encoding="utf-8") as f:
                f.write("success")
        print(f'[code check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] code access control inspection passed')
        sys.exit(0)


def init_args():
    parser = argparse.ArgumentParser()

    parser.add_argument('--repository_name', required=True, type=str, help='仓库名称')
    parser.add_argument('--pr_id', required=True, type=str, help='PR ID')

    # 【关键修改】参数名与 SCA/Anti-Poison 脚本完全对齐，分为扫描密钥和结果密钥
    parser.add_argument('--pr_scan_access_key', required=True, type=str, help='扫描 Access Key (APIG)')
    parser.add_argument('--pr_scan_secret_key', required=True, type=str, help='扫描 Secret Key (APIG)')
    parser.add_argument('--pr_result_access_key', required=True, type=str, help='结果查询 Access Key (APIG)')
    parser.add_argument('--pr_result_secret_key', required=True, type=str, help='结果查询 Secret Key (APIG)')

    parser.add_argument('--access_token', help='gitcode access token',required=False, type=str)
    
    parser.add_argument('--state_file', help='gitcode access token',required=True, type=str)
    parser.add_argument('--result_file', help='gitcode access token',required=True, type=str)

    # 注意：默认值处理。如果 codecheck_ip 传入的是完整域名+path，可能需要调整拼接逻辑
    # 这里保持原代码逻辑：codecheck_ip 默认为域名，prefix 默认为路径
    parser.add_argument('--codecheck_ip', default='https://apig.openlibing.com/openlibing-codecheck', type=str, help='APIG Gateway Domain')
    parser.add_argument('--gitcode_api', default='https://api.gitcode.com/api/v5/repos', type=str)
    parser.add_argument('--codecheck_prefix', default='/ci-portal/webhook/codecheck/v1', type=str)

    return parser.parse_args()

"""
--appId-task="${CREATE_TASK_AK}" \\
                                --secretKey-task="${CREATE_TASK_SK}" \\
                                --appId-status="${GET_RESULT_AK}" \\
                                --secretKey-status="${GET_RESULT_SK}"
                                
python3 codecheck.py --repository_name ${repo} --pr_id ${pr_id}  --pr_scan_access_key ${CREATE_TASK_AK} --pr_scan_secret_key ${CREATE_TASK_SK}  --pr_result_access_key ${GET_RESULT_AK} --pr_result_secret_key  ${GET_RESULT_SK} --state_file ${state_file} --result_file ${result_file}
 
"""

if __name__ == '__main__':
    args = init_args()

    codecheck = CodeCheck(
        scan_ak=args.pr_scan_access_key,
        scan_sk=args.pr_scan_secret_key,
        result_ak=args.pr_result_access_key,
        result_sk=args.pr_result_secret_key,
        access_token=args.access_token,
        state_file=args.state_file,
        result_file=args.result_file,
        pr_id=args.pr_id,
        repository_name=args.repository_name,
        codecheck_ip=args.codecheck_ip,
        gitcode_api=args.gitcode_api,
        codecheck_prefix=args.codecheck_prefix
    )
    codecheck.run()

