# -*- coding:utf-8 -*-
# Copyright (c) 2021 Huawei Technologies Co.,Ltd.
#
# openGauss is licensed under Mulan PSL v2.
# You can use this software according to the terms
# and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#
#          http://license.coscl.org.cn/MulanPSL2
#
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS,
# WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.
# ----------------------------------------------------------------------------

"""
CodeCheck代码检查，请求接口的脚本文件。
传入参数： pull request链接
输出参数： 执行完毕返回的libing平台任务路径的URL

required 3rd:
    requests
"""
import sys
import time
import datetime
import argparse
import os

import requests

# 正式环境
STATIC_KEY = ""
API_DOMAIN = "https://majun.osinfra.cn"
API_PREFIX = "/api/ci-backend/ci-portal/webhook/codecheck/v1"

CODE_SUCCESS = "200"
CODE_RUNNING = "100"
CODE_TOKEN_EXPIRATION = "401"


def print_logs(*args):
    now = datetime.datetime.fromtimestamp(time.time())
    print("%s: %s" % (now, ",".join(args)))


def parse_args():
    parser = argparse.ArgumentParser(description="""
    code check pull request parameters.""")
    parser.add_argument('--pull-id', type=str, required=True, help='pull request id.')
    parser.add_argument('--repo-url', type=str, required=True, help='target repo url.')
    parser.add_argument('--seed', type=str, required=True, help='seed.')
    return parser.parse_args()


class CcRequest:

    def __init__(self):
        self.token = ""
        self.task_id = ""
        self.uuid = ""
        # self.pull_request_url = "https://gitee.com/opengauss/openGauss-OM/pulls/201"
        self.pull_request_url = ""
        self.pr_id = ""
        self.repo_name = ""
        self.cc_result_dir = ""
        self.result_file = ""
        self.state_file = ""
        # 时间戳
        self.seed = 0
        self.state = ""
        self.url = ""

    def exit_with_msg(self, step, msg):
        print_logs(step, msg)
        with open(self.state_file, "w+") as fd:
            fd.write("failed")
            sys.exit(1)

    def create_cc_result_dir(self):
        if not os.path.exists(self.cc_result_dir):
            os.makedirs(self.cc_result_dir)

    def write_empty_value(self):
        print(self.seed)
        self.result_file = os.path.join(os.path.abspath(self.cc_result_dir), "cc_result_" + self.seed)
        self.state_file = os.path.join(os.path.abspath(self.cc_result_dir), "cc_state_" + self.seed)
        print(self.result_file)
        print(self.state_file)
        with open(self.result_file, "w+") as fd:
            fd.write("")
        with open(self.state_file, "w+") as fd:
            fd.write("")

    def write_result_to_file(self, res):
        print_logs("state file is", self.state_file)
        print_logs("result ile is", self.result_file)
        if res.get('code') == CODE_SUCCESS:
            if res.get('state') == 'pass':
                with open(self.state_file, 'w+') as fd:
                    fd.write("success")
            else:
                with open(self.state_file, 'w+') as fd:
                    fd.write("failed")
            with open(self.result_file, 'w+') as fd:
                fd.write(res.get('data', ''))
        else:
            with open(self.state_file, 'w+') as fd:
                fd.write("failed")

    def query_check_result(self):
        print_logs('start query task......')
        status_url = f'{API_DOMAIN}{API_PREFIX}/task/status'
        print_logs('status_url:' + status_url)
        body = {
            "uuid": self.uuid,
            "task_id": self.task_id,
            "token": self.token
        }
        while True:
            # 每10s查询一次
            time.sleep(10)
            try:
                response = requests.post(status_url, json=body, timeout=10)
                print_logs(f"response is {response.text}")
                res = response.json()
                if res.get('code') == CODE_SUCCESS:
                    self.url = res.get('data')
                    self.state = res.get('state')
                    print_logs('task success')
                    # 将结果写入文件中
                    self.write_result_to_file(res)
                    print_logs("write_result_to_file end")
                    break
                elif res.get('code') == CODE_RUNNING:
                    print_logs('task running')
                    continue
                elif res.get('code') == CODE_TOKEN_EXPIRATION:
                    print_logs('token expired')
                    self.get_token()
                    continue
                else:
                    self.exit_with_msg('task failed', res.get('msg'))
                    self.write_result_to_file(res)
                    break
            except Exception as e:
                print_logs(str(e))
                continue

    def create_task(self):
        print_logs('start create task......')
        try:
            task_url = f'{API_DOMAIN}{API_PREFIX}/task'
            print_logs(f'task_url:{task_url}')
            body = {
                "pr_url": self.pull_request_url,
                "token": self.token
            }
            response = requests.post(task_url, json=body, timeout=10)
            print_logs(f'create_task_result:{response.text}')
            res = response.json()
            if res.get('code') == CODE_SUCCESS:
                self.uuid = res.get('uuid')
                self.task_id = res.get('task_id')
                print_logs('create task success')
            else:
                self.exit_with_msg('create task failed')
        except Exception as e:
            self.exit_with_msg('create task exception', e)

    def get_token(self):
        print_logs('start get token......')
        try:
            token_url = f'{API_DOMAIN}{API_PREFIX}/token'
            print(f'token_url: {API_DOMAIN}{API_PREFIX}/token')
            body = {
                "static_token": STATIC_KEY
            }
            response = requests.post(token_url, json=body, timeout=10)
            res = response.json()
            if res.get('code') == CODE_SUCCESS:
                self.token = res.get('data')
                print_logs('get token success')
            else:
                self.exit_with_msg('get token failed')
        except Exception as e:
            self.exit_with_msg('get token exception', e)

    def generate_pr_url(self, prid, repo, seed):
        repo_url = repo[:-4]
        self.pull_request_url = "%s/pulls/%s" % (repo_url, prid)
        print("pull_request_url:" + self.pull_request_url)
        self.pr_id = self.pull_request_url.split("/")[-1]
        print('pr_id:' + self.pr_id)
        self.repo_name = self.pull_request_url.split("/")[-3]
        print('repo_name:' + self.repo_name)
        self.cc_result_dir = ("/tmp/cc_result/%s/%s" % (self.repo_name, self.pr_id))
        print('cc_result_dir:' + self.cc_result_dir)
        self.seed = seed
        print('seed:' + self.seed)

    def start(self):
        print_logs("################# start to run Code Check #################")
        params = parse_args()
        self.generate_pr_url(params.pull_id, params.repo_url, params.seed)
        self.create_cc_result_dir()
        self.write_empty_value()
        self.get_token()
        self.create_task()
        self.query_check_result()


if __name__ == '__main__':
    req = CcRequest()
    req.start()
