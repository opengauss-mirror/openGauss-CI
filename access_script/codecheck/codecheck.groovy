#!groovy
/*
 openGauss静态检查门禁，该脚本目前已经集成：
    1. codecheck 代码检查

 任务管理：
    任务调度机器： scanner-manager
    任务执行机器： scanner-slave
    执行方式： codecheck通过调用scanner-slave节点来执行。

 依赖关系：
    1. codecheck 依赖
        codecheck_request.py 用于发送pr地址到远程服务器，并等待codecheck完毕回传libing平台的任务url地址
*/
import java.util.Date;

def time = new Date().format('yyyyMMddHHmmss')

// codecheck
def checkResult = ""
def checkState = "failed"

// labels
def codeCheckFailedLabel = "codecheck-failed"
def codeCheckSuccessLabel = "codecheck-success"
def codeCheckRunningLabel = "codecheck-running"

// enable
def enableCodeCheck = true

def deleteLabel(namespace, repo, prNumber, label, token) {
    println("Delete labels")
    String response = null

    def requestUrl = "https://gitee.com/api/v5/repos/" + namespace + "/" + repo + "/pulls/" + prNumber + "/labels/" + label
    println requestUrl
    def auth_token = "Authorization: Bearer " + token
    def header = "Content-Type: application/json;charset=UTF-8"
    response = sh(script: "curl -X DELETE $requestUrl -H '$auth_token' -H '$header'", returnStdout: true).trim()

    println("delete ${label} success")
}

def addLabel(namespace, repo, prNumber, label, token) {
    println("Delete ${label} labels")
    String response = null

    def requestUrl = "https://gitee.com/api/v5/repos/" + namespace + "/" + repo + "/pulls/" + prNumber + "/labels"
    def updatedLabels = """["$label"]"""
    println requestUrl
    def auth_token = "Authorization: Bearer " + token
	def header = "Content-Type: application/json"
	response = sh(script: "curl -X POST $requestUrl -H '$auth_token' -H '$header' -d '$updatedLabels'", returnStdout: true).trim()

    println("add ${label} success")
}

def printComments(enableCodeCheck, checkState, prNumber, checkResult) {
    def comments = "\n 静态检查 \n" +
            "|  Check Name  |  Build Details  |  Check Result  | Check Detail | \n" +
            "|  -------------  |  -------------  |  -------------  |  -------------  |\n"

    if (enableCodeCheck) {
        if (checkState != "failed") {
            // jenkins_work：表示流水线地址
            comments +=
                    "|  CodeCheck  |  [#${BUILD_ID}](${jenkins_work}/${BUILD_ID}/console) | :white_check_mark: 通过 | [>>>](${checkResult}) |\n"
        } else {
            comments +=
                    "|  CodeCheck  |  [#${BUILD_ID}](${jenkins_work}/${BUILD_ID}/console) | :warning: 不通过 | [>>>](${checkResult}) |\n"
        }
    }

    addGiteeMRComment comment: comments
}

def processResult(checkState, codeCheckSuccessLabel, codeCheckRunningLabel, codeCheckFailedLabel) {
    if (checkState == "success") {
        println("codecheck sucess")
        withCredentials([string(credentialsId: 'gitee_token_id', variable: 'GITEE_TOKEN')]) {
            addLabel("${giteeTargetNamespace}", "${giteeTargetRepoName}", "${giteePullRequestIid}", codeCheckSuccessLabel, "${GITEE_TOKEN}")
            deleteLabel("${giteeTargetNamespace}", "${giteeTargetRepoName}", "${giteePullRequestIid}", codeCheckRunningLabel, "${GITEE_TOKEN}")
        }
    } else {
        println("codecheck failed")
        withCredentials([string(credentialsId: 'gitee_token_id', variable: 'GITEE_TOKEN')]) {
            addLabel("${giteeTargetNamespace}", "${giteeTargetRepoName}", "${giteePullRequestIid}", codeCheckFailedLabel, "${GITEE_TOKEN}")
            deleteLabel("${giteeTargetNamespace}", "${giteeTargetRepoName}", "${giteePullRequestIid}", codeCheckRunningLabel, "${GITEE_TOKEN}")
        }
    }
}

pipeline {
    agent {
        node {
            label "xxx"
        }
    }
    environment {
        seed = "${time}"
    }
    stages {
        stage('Init') {
            steps('Init step') {
                script {
                    echo "############ Delete Tag ##############"

                    echo "${giteeTargetNamespace}"
                    echo "${giteeTargetRepoName}"
                    echo "${giteePullRequestIid}"

                    withCredentials([string(credentialsId: 'gitee_token_id', variable: 'GITEE_TOKEN')]) {
                        deleteLabel("${giteeTargetNamespace}", "${giteeTargetRepoName}", "${giteePullRequestIid}", codeCheckFailedLabel, "${GITEE_TOKEN}")
                        deleteLabel("${giteeTargetNamespace}", "${giteeTargetRepoName}", "${giteePullRequestIid}", codeCheckSuccessLabel, "${GITEE_TOKEN}")
                        echo "############ Add Tag ##############"
                        addLabel("${giteeTargetNamespace}", "${giteeTargetRepoName}", "${giteePullRequestIid}", codeCheckRunningLabel, "${GITEE_TOKEN}")
                    }
                }
            }
        }
        stage('CodeCheck') {
            when {
                expression {
                    enableCodeCheck
                }
            }
            steps('codecheck-steps') {
                script {

                    def result_file = "/tmp/cc_result/${giteeTargetRepoName}/${giteePullRequestIid}/cc_result_${seed}"
                    def state_file = "/tmp/cc_result/${giteeTargetRepoName}/${giteePullRequestIid}/cc_state_${seed}"

                    println(result_file)
                    println(state_file)
                    sh '''
                            repo=${giteeTargetRepoName}
                            pr_id=${giteePullRequestIid}
                            repo_url=${giteeTargetRepoHttpUrl}
                            result_file=/tmp/cc_result/${repo}/${pr_id}/cc_result_${seed}
                            state_file=/tmp/cc_result/${repo}/${pr_id}/cc_state_${seed}
                            echo "$result_file"
                            echo "$state_file"
                            echo "${seed}"

                            if [ -f $result_file ]; then
                                rm  $result_file
                            fi
                            if [ -f $state_file ]; then
                                rm  $state_file
                            fi

                            python3 /data/codecheck_request.py --pull-id=${pr_id} --repo-url=${repo_url} --seed=${seed}
                            '''

                    checkResult = readFile(result_file)
                    println(checkResult)
                    checkState = readFile(state_file)
                    println(checkState)
                    sh "echo '......end......'"
                }
            }
        }
    }

    post {
        success {
            script {
                retry(3) {
                    echo '-------------------post success-------------------'
                    // 输出评论
                    printComments(enableCodeCheck, checkState, "${giteePullRequestIid}", checkResult)
                    // 打印codecheck标签
                    processResult(checkState, codeCheckSuccessLabel, codeCheckRunningLabel, codeCheckFailedLabel)
                }
            }
        }
        unsuccessful {
            script {
                retry(3) {
                    echo "-------------------post failed-------------------"
                    printComments(enableCodeCheck, checkState, "${giteePullRequestIid}", checkResult)
                    processResult(checkState, codeCheckSuccessLabel, codeCheckRunningLabel, codeCheckFailedLabel)
                }
            }
        }
    }
}