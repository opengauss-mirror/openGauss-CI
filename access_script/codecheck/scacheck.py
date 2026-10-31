#
# Copyright (c) Huawei Technologies CO., Ltd. 2022-2026. All rights reserved.
# https://gitcode.com/Richard-bean/lidebin/releases/2026-2-9
#
import datetime
import json
import sys
import time
import argparse
import requests

# 【关键】必须引入 APIG SDK 进行标准签名
try:
    from apig_sdk import signer
except ImportError:
    print("Error: apig_sdk not found. Please install it via 'pip install apig-sdk' or check your python environment.")
    sys.exit(1)

class Sca(object):

    def __init__(self, scan_ak, scan_sk, result_ak, result_sk, access_token, pr_id, repository_name,
                 codecheck_ip='https://apig.openlibing.com',
                 gitcode_api='https://api.gitcode.com/api/v5/repos',
                 codecheck_prefix='/openlibing-sca'):
        self.pr_url = None
        self.scanId = None
        self.result = None
        self.report_url = None

        # 四把钥匙
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

    def _get_pr_url(self):
        self.pr_url = f"{self.gitcode_domian}/{self.repository_name}/pull/{self.pr_id}"
        print(f"pr_url: {self.pr_url}")

    def _get_create_task(self):
        """
        使用 [Scan AK/SK] + [APIG 标准 SDK] 进行签名
        """
        try:
            task_url = f'{self.codecheck_ip}{self.codecheck_prefix}/scan/pr'
            params = {
                "prUrl": self.pr_url,
                "projectName": "openGauss"
            }
            body = json.dumps(params)

            method = 'POST'
            headers = {"Content-Type": "application/json"}

            # --- 核心修改：使用 APIG SDK 签名 ---
            request = signer.HttpRequest(method, task_url, headers, body)
            sig = signer.Signer()
            sig.Key = self.scan_ak      # 使用扫描密钥
            sig.Secret = self.scan_sk   # 使用扫描密钥
            sig.Sign(request)
            # SDK 会自动在 request.headers 中加入 Authorization, X-Sdk-Date 等标准头
            # ----------------------------------

            print(f"[Create Task] URL: {task_url}")

            responsetemp = requests.request(
                request.method,
                request.scheme + "://" + request.host + request.uri,
                headers=request.headers, # 使用 SDK 签名后的 headers
                data=request.body
            )

            print(f"[Create Task] 响应状态码: {responsetemp.status_code}")
            # 调试时可开启下方打印
            # print(f"[Create Task] 响应内容: {responsetemp.text}")

            try:
                response = responsetemp.json()
            except ValueError as e:
                print("无法解析 JSON 响应")
                print(f'[sca check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] 无法解析 JSON 响应 \n[{e}]')
                return

            if response.get('code') == 200:
                self.scanId = response.get('data')
                print(f'[sca check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] create task success')
            else:
                print(f'[sca check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] create task failed '
                      f'\n[{response.get("msg")}]')
        except Exception as e:
            print(f'[sca check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] create task error \n[{e}]')

    def _get_task_result(self):
        """
        使用 [Result AK/SK] + [APIG 标准 SDK] 进行签名
        """
        expire_time = 0
        while expire_time < 1800:
            time.sleep(10)
            try:
                status_url = f'{self.codecheck_ip}{self.codecheck_prefix}/scan/result?scanId=' + self.scanId;
                print(f"self.scanId: {self.scanId}")
                # 初始化签名器并设置密钥
                sig = signer.Signer()
                sig.Key = self.result_ak
                sig.Secret = self.result_sk
                method = "GET"
                headers = {"host": "apig.openlibing.com"}
                # sign
                r = signer.HttpRequest(method, status_url, headers)
                sig.Sign(r)
                responsetemp = requests.request(method, status_url, headers=r.headers)
                # 输出结果
                print(f"响应状态码: {responsetemp.status_code}")
                print(f"响应内容: {responsetemp.text}")  # 查看实际返回的内容
                response = responsetemp.json()
                if response.get('code') == 200:
                    data = response.get('data')
                    state = data.get('state')
                    self.report_url = data.get('prResult')

                    if state == 'success':
                        if data.get('unconfirmedFileNum') == 0:
                            self.result = 'pass'
                            print(f"FINAL_RESULT:{self.result}")
                        elif data.get('unconfirmedFileNum') > 0:
                            self.result = 'no pass'
                            print(f"FINAL_RESULT:{self.result}")
                            print(f"SCA_UNCONFIRMED_NUM:{data.get('unconfirmedFileNum')}")
                        print(f'[code check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] task success')
                        print(f"FINAL_REPORT_URL:{self.report_url}")
                        print(f"SCA_STATE:{state}")
                        break
                    elif state == 'scanning':
                        expire_time = expire_time + 20
                        continue
                    elif state == 'failure':
                        print(f"SCA_STATE:{state}")
                        print(f"FINAL_RESULT:{self.result}")
                        print(f'[code check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] task failure')
                        break
                else:
                    print(f'[code check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] task failed '
                          f'\n[{response.get("msg")}]')
                    break
            except Exception as e:
                print(f'[code check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] task error \n[{e}]')
                break

    def run(self):
        self._get_pr_url()
        if not self.pr_url:
            print(f'[sca check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] Error: pr_url is null')
            sys.exit(-1)

        self._get_create_task()
        if not self.scanId:
            print(f'[sca check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] create codecheck task error: missing scanId')
            sys.exit(-1)

        self._get_task_result()
        if not self.report_url:
            print(f'[sca check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] Error: report_url is null')
            sys.exit(-1)

        print(f'openlibing_url:{self.report_url}')

        if self.result != "pass":
            print(f'[sca check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] Access control check failed')
            sys.exit(-1)

        print(f'[sca check {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}] code access control inspection passed')
        sys.exit(0)



def init_args():
    parser = argparse.ArgumentParser()

    parser.add_argument('--repository_name', required=True, type=str, help='仓库名称')
    parser.add_argument('--pr_id', required=True, type=str, help='PR ID')

    # 【修改点】参数名从 version_ 改为 pr_
    parser.add_argument('--pr_scan_access_key', required=True, type=str, help='扫描 Access Key (APIG)')
    parser.add_argument('--pr_scan_secret_key', required=True, type=str, help='扫描 Secret Key (APIG)')
    parser.add_argument('--pr_result_access_key', required=True, type=str, help='结果查询 Access Key (APIG)')
    parser.add_argument('--pr_result_secret_key', required=True, type=str, help='结果查询 Secret Key (APIG)')

    parser.add_argument('--access_token', help='gitcode access token', required=True, type=str)

    # 默认值建议改为你的 APIG 域名
    parser.add_argument('--codecheck_ip', default='https://apig.openlibing.com', type=str, help='APIG Gateway URL')
    parser.add_argument('--gitcode_api', default='https://api.gitcode.com/api/v5/repos', type=str)
    parser.add_argument('--codecheck_prefix', default='/openlibing-sca', type=str)

    return parser.parse_args()

"""
${CREATE_TASK_AK}' '${CREATE_TASK_SK}' '${GET_RESULT_AK}' '${GET_RESULT_SK}

--repository_name ${REPO} --pr_id ${NUMBER} --pr_scan_access_key  ${CREATE_TASK_AK} --pr_scan_secret_key ${CREATE_TASK_SK}  --pr_result_access_key ${GET_RESULT_AK} --pr_result_secret_key ${GET_RESULT_SK}
"""


if __name__ == '__main__':
    args = init_args()

    sca = Sca(
        # 【修改点】这里接收的参数名也对应改为 pr_ 开头
        scan_ak=args.pr_scan_access_key,
        scan_sk=args.pr_scan_secret_key,
        result_ak=args.pr_result_access_key,
        result_sk=args.pr_result_secret_key,
        access_token=args.access_token,
        pr_id=args.pr_id,
        repository_name=args.repository_name,
        codecheck_ip=args.codecheck_ip,
        gitcode_api=args.gitcode_api,
        codecheck_prefix=args.codecheck_prefix
    )
    sca.run()
