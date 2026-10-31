#!groovy
/*
 openGauss静态检查门禁，该脚本目前已经集成：
    1. codecheck 代码检查

 修改说明：
    1. CodeCheck使用独立的AK/SK（两组：创建任务和查询结果）
    2. 使用Python SDK进行AK/SK认证
    3. 修正Python脚本路径和参数传递
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

    def requestUrl = "https://api.gitcode.com/api/v5/repos/" + namespace + "/" + repo + "/pulls/" + prNumber + "/labels/" + label
    println requestUrl
    println requestUrl
    def auth_token = "Authorization: Bearer " + token
    def header = "Content-Type: application/json;charset=UTF-8"
    response = sh(script: "curl -X DELETE $requestUrl -H '$auth_token' -H '$header'", returnStdout: true).trim()
    println("delete ${label} success")
}

def addLabel(namespace, repo, prNumber, label, token) {
    println("Delete ${label} labels")
    String response = null

    def requestUrl = "https://api.gitcode.com/api/v5/repos/" + namespace + "/" + repo + "/pulls/" + prNumber + "/labels"
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
            comments +=
                    "|  CodeCheck  |  [#${BUILD_ID}](https://jenkins.opengauss.org/view/static_check/job/openGauss_CodeCheck_PR/${BUILD_ID}/console) | :white_check_mark: 通过 | [>>>](${checkResult}) |\n"
        } else {
            comments +=
                    "|  CodeCheck  |  [#${BUILD_ID}](https://jenkins.opengauss.org/view/static_check/job/openGauss_CodeCheck_PR/${BUILD_ID}/console) | :warning: 不通过 | [>>>](${checkResult}) |\n"
        }
    }

    addGitcodeMRComment comment: comments
}

def processResult(checkState, codeCheckSuccessLabel, codeCheckRunningLabel, codeCheckFailedLabel) {
    if (checkState == "success") {
        println("codecheck success")
        withCredentials([string(credentialsId: 'opengauss_bot-gitcode-token', variable: 'GITCODE_TOKEN')]) {
            addLabel("${gitcodeTargetNamespace}", "${gitcodeTargetRepoName}", "${gitcodePullRequestIid}", codeCheckSuccessLabel, "${GITCODE_TOKEN}")
            deleteLabel("${gitcodeTargetNamespace}", "${gitcodeTargetRepoName}", "${gitcodePullRequestIid}", codeCheckRunningLabel, "${GITCODE_TOKEN}")
            deleteLabel("${gitcodeTargetNamespace}", "${gitcodeTargetRepoName}", "${gitcodePullRequestIid}", codeCheckFailedLabel, "${GITCODE_TOKEN}")
        }
    } else {
        println("codecheck failed")
        withCredentials([string(credentialsId: 'opengauss_bot-gitcode-token', variable: 'GITCODE_TOKEN')]) {
            addLabel("${gitcodeTargetNamespace}", "${gitcodeTargetRepoName}", "${gitcodePullRequestIid}", codeCheckFailedLabel, "${GITCODE_TOKEN}")
            deleteLabel("${gitcodeTargetNamespace}", "${gitcodeTargetRepoName}", "${gitcodePullRequestIid}", codeCheckRunningLabel, "${GITCODE_TOKEN}")
        }
    }
}

pipeline {
    agent {
        node {
            label "CentOS-build || openEuler-build-01 || openEuler-build-02"
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

                    echo "${gitcodeTargetNamespace}"
                    echo "${gitcodeTargetRepoName}"
                    echo "${gitcodePullRequestIid}"

                    withCredentials([string(credentialsId: 'opengauss_bot-gitcode-token', variable: 'GITCODE_TOKEN')]) {
                        deleteLabel("${gitcodeTargetNamespace}", "${gitcodeTargetRepoName}", "${gitcodePullRequestIid}", codeCheckFailedLabel, "${GITCODE_TOKEN}")
                        deleteLabel("${gitcodeTargetNamespace}", "${gitcodeTargetRepoName}", "${gitcodePullRequestIid}", codeCheckSuccessLabel, "${GITCODE_TOKEN}")
                        echo "############ Add Tag ##############"
                        addLabel("${gitcodeTargetNamespace}", "${gitcodeTargetRepoName}", "${gitcodePullRequestIid}", codeCheckRunningLabel, "${GITCODE_TOKEN}")
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
                    withCredentials([
                        // 创建任务使用的AK/SK
                        string(credentialsId: 'codecheck_create_task_access_key', variable: 'CREATE_TASK_AK'),
                        string(credentialsId: 'codecheck_create_task_secret_key', variable: 'CREATE_TASK_SK'),
                        // 查询结果使用的AK/SK
                        string(credentialsId: 'codecheck_get_result_access_key', variable: 'GET_RESULT_AK'),
                        string(credentialsId: 'codecheck_get_result_secret_key', variable: 'GET_RESULT_SK')
                    ]) {
                        def result_file = "/tmp/cc_result/${gitcodeTargetRepoName}/${gitcodePullRequestIid}/cc_result_${seed}"
                        def state_file = "/tmp/cc_result/${gitcodeTargetRepoName}/${gitcodePullRequestIid}/cc_state_${seed}"

                        println("Result file: ${result_file}")
                        println("State file: ${state_file}")
                        
                        // 创建结果目录
                        sh """
                            mkdir -p /tmp/cc_result/${gitcodeTargetRepoName}/${gitcodePullRequestIid}
                        """
                        
                        // 修正：使用正确的Python脚本路径，并确保参数传递正确
                        sh """
                            #!/bin/bash
                            export PYTHONPATH=/data/scacheck/apig
                            
                            repo=${gitcodeTargetRepoName}
                            pr_id=${gitcodePullRequestIid}
                            repo_url=${gitcodeTargetRepoHttpUrl}
                            result_file=/tmp/cc_result/\${repo}/\${pr_id}/cc_result_${seed}
                            state_file=/tmp/cc_result/\${repo}/\${pr_id}/cc_state_${seed}
                            
                            
                            if [ -f \${result_file} ]; then
                                rm \${result_file}
                            fi
                            if [ -f \${state_file} ]; then
                                rm \${state_file}
                            fi
                            
                            # 打印调试信息
                            echo "PYTHONPATH: \$PYTHONPATH"
                            echo "Python script: /data/codecheck.py"
                            echo "pull-id: \${pr_id}"
                            echo "repo-url: \${repo_url}"
                            
                            # 执行Python脚本
                            python3 /data/scacheck/codecheck.py --repository_name ${gitcodeTargetRepoName} --pr_id ${gitcodePullRequestIid}  --pr_scan_access_key ${CREATE_TASK_AK} --pr_scan_secret_key ${CREATE_TASK_SK}  --pr_result_access_key ${GET_RESULT_AK} --pr_result_secret_key  ${GET_RESULT_SK} --state_file ${state_file} --result_file ${result_file}
                            
                            # 检查执行结果
                            if [ \$? -ne 0 ]; then
                                echo "Python script execution failed"
                                exit 1
                            fi
                        """

                        // 等待文件生成
                        sleep 2
                        
                        // 读取结果文件
                        if (fileExists(result_file)) {
                            checkResult = readFile(result_file).trim()
                            println("CodeCheck result: ${checkResult}")
                        } else {
                            println("Result file not found: ${result_file}")
                            checkResult = ""
                        }
                        
                        if (fileExists(state_file)) {
                            checkState = readFile(state_file).trim()
                            println("CodeCheck state: ${checkState}")
                        } else {
                            println("State file not found: ${state_file}")
                            checkState = "failed"
                        }
                        
                        sh "echo '......codecheck end......'"
                    }
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
                    printComments(enableCodeCheck, checkState, "${gitcodePullRequestIid}", checkResult)
                    
                    // 打印codecheck标签
                    withCredentials([string(credentialsId: 'opengauss_bot-gitcode-token', variable: 'GITCODE_TOKEN')]) {
                        processResult(checkState, codeCheckSuccessLabel, codeCheckRunningLabel, codeCheckFailedLabel)
                    }
                }
            }
        }
        unsuccessful {
            script {
                retry(3) {
                    echo "-------------------post failed-------------------"
                    printComments(enableCodeCheck, checkState, "${gitcodePullRequestIid}", checkResult)
                    
                    withCredentials([string(credentialsId: 'opengauss_bot-gitcode-token', variable: 'GITCODE_TOKEN')]) {
                        processResult(checkState, codeCheckSuccessLabel, codeCheckRunningLabel, codeCheckFailedLabel)
                    }
                }
            }
        }
    }
}