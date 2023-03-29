#!groovy
/*
 openGauss静态检查门禁，该脚本目前已经集成：
    1. scanoss 开源引用扫描

 任务管理：
    任务调度机器： scanner-manager
    任务执行机器： scanner-slave
    执行方式： scanoss通过调用scanner-slave节点来执行。

 依赖关系：
    1. scanoss 依赖
        scanner.py发送数据并接收检查结果
        parse_json_file.py 解析检查结果，生成html文件用于展示
        black.json配置白名单，在白名单上面的项目不进行扫描

        -- 更新 2021-12-08
        scanoss更新为插件方式管理
*/
import groovy.json.*
// scanoss
def scanoss_state = ''
def scanoss_result_url = ''

// labels
def codeCheckFailedLabel = "scnaoss-failed"
def codeCheckSuccessLabel = "scnaoss-success"
def codeCheckRunningLabel = "scnaoss-running"

// enable
def enable_scanosss = true

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

def printComments(enable_scanosss, scanoss_state, prNumber, scanoss_result_url) {
    def comments = "\n 静态检查 \n" +
            "|  Check Name  |  Build Details  |  Check Result  | Check Detail | \n" +
            "|  -------------  |  -------------  |  -------------  |  -------------  |\n"

    if (enable_scanosss) {
        if (scanoss_state != "failed") {
            // jenkins_work：表示流水线地址
            comments +=
                    "|  CodeCheck  |  [#${BUILD_ID}](${jenkins_work}/${BUILD_ID}/console) | :white_check_mark: 通过 | [>>>](${scanoss_result_url}) |\n"
        } else {
            comments +=
                    "|  CodeCheck  |  [#${BUILD_ID}](${jenkins_work}/${BUILD_ID}/console) | :warning: 不通过 | [>>>](${scanoss_result_url}) |\n"
        }
    }

    addGiteeMRComment comment: comments
}

def processResult(scanoss_state, codeCheckSuccessLabel, codeCheckRunningLabel, codeCheckFailedLabel) {
    if (scanoss_state == "success") {
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
        stage ("ScanossCheck") {
            when {
                expression {
                    enable_scanosss
                }
            }
            steps ('sonar-steps') {
                script {
                    echo "########## Scanoss Build Number is : ${BUILD_NUMBER} ##########"
                    echo "########## Repo Url: ${giteeTargetRepoHttpUrl} and Pull Request Id ${giteePullRequestIid} ##########"
                    
                    sca authCode: '', credentialsId: '', method: 'WebHook', methodChoose: '', sbomFile: '/data/black.json', scanossCredentials: '', sourceFile: '', sudoOrder: 'sudo', url: '', urlChoose: '1'

                    def resultjsonfile = readFile( "${WORKSPACE}/scanoss_result_${BUILD_NUMBER}.json" )

                    def slurper = new JsonSlurper();
                    def result = slurper.parseText(resultjsonfile);
                    echo "result.result ${result}"
                    
                    if (result.result == "failed") {
                        echo "开源片段检查失败"
                        scanoss_state = "failed"
                    } else {
                        echo "开源片段检查成功"
                        scanoss_state = "success"
                    }
                    scanoss_result_url = result.reportUrl
                    echo "开源片段检查结果： ${scanoss_result_url}"
                }
                
            }
        }
    }

    post {
        success {
            script {
                retry(3) {
                    echo "-------------------post success-------------------"
                    printComments(enable_scanosss, scanoss_state, "${giteePullRequestIid}", scanoss_result_url)
                    // 打印scanosscheck标签
                    processResult(scanoss_state, codeCheckSuccessLabel, codeCheckRunningLabel, codeCheckFailedLabel)
                }
            }
        }
        unsuccessful {
            script {
                retry(3) {
                    echo "-------------------post failed-------------------"
                    printComments(enable_scanosss, scanoss_state, "${giteePullRequestIid}", scanoss_result_url)
                    processResult(scanoss_state, codeCheckSuccessLabel, codeCheckRunningLabel, codeCheckFailedLabel)
                }
            }
        }
    }
}