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

STATIC_KEY = ""
API_DOMAIN = ""
API_GET_DYNAMIC_TOKEN = "/api/openlibing/codecheck/token/%s" % STATIC_KEY
API_CREATE_TASK = "/api/openlibing/codecheck/task"
API_QUERY_STATUS = "/api/openlibing/codecheck/{task_id}/status"

CODE_SUCCESS = 200
QUERY_TIMER = 30

STEP_Q_TOKEN = "query token:"
STEP_C_TASK = "create task:"
STEP_Q_STATUS = "query status:"

RESULT_PASS = "pass"
RESULT_FAILED = "no pass"


def print_logs(*args):
    tm = datetime.datetime.fromtimestamp(time.time())
    print("%s: %s" % (tm, ",".join(args)))


def parse_args():
    parser = argparse.ArgumentParser(description="""code check pull request parameters.""")
    parser.add_argument('--pull-id', type=str, required=True, help='pull request id.')
    parser.add_argument('--repo-url', type=str, required=True, help=' target repo url.')
    parser.add_argument('--seed', type=str, required=True, help='seed.')
    return parser.parse_args()


class CCRequest:

    def __init__(self):
        self.__token = ""
        self.__task_id = ""
        self.__uuid = ""
        self.pull_request_url = ""
        self.pr_id = ""
        self.repo_name = ""
        self.cc_result_dir = ""
        self.result_file = ""
        self.state_file = ""
        self.seed = 0

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
        self.result_file = os.path.join(os.path.abspath(self.cc_result_dir), "cc_result_" + str(self.seed))
        self.state_file = os.path.join(os.path.abspath(self.cc_result_dir), "cc_state_" + str(self.seed))
        print(self.result_file)
        print(self.state_file)
        with open(self.result_file, "w+") as fd:
            fd.write("")
        with open(self.state_file, "w+") as fd:
            fd.write("")

    def start(self):
        print_logs("################# start to run Code Check #################")
        params = parse_args()
        self.generate_pr_url(params.pull_id, params.repo_url, params.seed)
        self.create_cc_result_dir()
        self.write_empty_value()
        self.get_token()
        self.create_task()
        while True:
            result = self.query_check_result()
            print_logs(str(result))
            if result.get("task_end"):
                break
            time.sleep(QUERY_TIMER)
        # 检查结果写入临时文件，提供给shell脚本获取
        print(result)
        url = result.get("url")

        with open(self.result_file, "w+") as fd:
            fd.write(url)

        if result.get("state") != RESULT_FAILED:
            with open(self.state_file, "w+") as fd:
                fd.write("success")
        else:
            with open(self.state_file, "w+") as fd:
                fd.write("failed")

    def query_check_result(self):
        returndata = {
            "task_end": False,
            "state": RESULT_PASS,
            "url": ""
        }
        param = {
            "token": self.__token,
            "uuid": self.__uuid
        }
        rps = requests.get(
            API_DOMAIN + API_QUERY_STATUS.replace("{task_id}", self.__task_id), params=param, timeout=5)
        if rps.status_code == CODE_SUCCESS:
            result = rps.json()
            code = result.get("code")
            if code == "100":
                returndata["task_end"] = False
            elif code == "200":
                returndata["task_end"] = True
                returndata["state"] = result.get("state")
                returndata["url"] = result.get("data")
            elif code == "500":
                returndata["task_end"] = True
                if result.get("msg").find("There is no proper set of languages") != -1:
                    returndata["state"] = RESULT_PASS
            else:
                returndata["task_end"] = True
        else:
            self.exit_with_msg(STEP_Q_STATUS, rps.text)

        return returndata

    def create_task(self):
        param = {
            "token": self.__token,
            "pr_url": self.pull_request_url
        }
        rps = requests.get(API_DOMAIN + API_CREATE_TASK, params=param, timeout=5)
        print("rps--------------- %s" % rps)
        self.check_task_result(rps)
        print_logs("create task request success")

    def check_task_result(self, rps):
        if CODE_SUCCESS == rps.status_code:
            result = rps.json()
            print(result)
            if result.get("code") == "200":
                self.__task_id = result.get("task_id")
                self.__uuid = result.get("uuid")
            elif result.get("msg").find("There is no proper set of languages") != -1:
                with open(self.state_file, "w+") as fd:
                    fd.write("success")
                sys.exit(0)
            else:
                self.exit_with_msg(STEP_C_TASK, result.get("msg"))
        else:
            self.exit_with_msg(STEP_C_TASK, rps.text)

    def get_token(self):
        print_logs("start get token......")
        rps = requests.get(API_DOMAIN + API_GET_DYNAMIC_TOKEN, timeout=5)
        if CODE_SUCCESS == rps.status_code:
            result = rps.json()
            if result.get("code") != "200":
                self.exit_with_msg(STEP_Q_TOKEN, result.get("msg"))
            self.__token = result.get("data")
        else:
            self.exit_with_msg(STEP_Q_TOKEN, rps.text)
        print_logs("get token query success")

    def generate_pr_url(self, prid, repo, seed):
        repo_url = repo[:-4]
        self.pull_request_url = "%s/pull/%s" % (repo_url, prid)
        self.pr_id = self.pull_request_url.split("/")[-1]
        self.repo_name = self.pull_request_url.split("/")[-3]
        self.cc_result_dir = ("/tmp/cc_result/%s/%s" % (self.repo_name, self.pr_id))
        self.seed = seed


if __name__ == '__main__':
    req = CCRequest()
    req.start()
