import groovy.json.JsonSlurperClassic

def deleteLabel(namespace, repo, prNumber, label, token) {
    println("Delete labels")
    def requestUrl = 'https://api.gitcode.com/api/v5/repos/' + namespace + '/' + repo + "/pulls/" + prNumber + "/labels/" + label
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

def printComments(map, jobName) {
    def comments = "\n 开源片段扫描 \n" +
            "|  Check Name  |  Build Details  |  Check Result  | Check Detail | \n" +
            "|  -------------  |  -------------  |  -------------  |  -------------  |\n"
    url = "https://jenkins.opengauss.org/job/${jobName}/${BUILD_ID}/console"
    if (map.get("status") == "pass") {
        comments +=
                "|  sca  |  [#${BUILD_ID}](${url}) | :white_check_mark: 通过 | [>>>](${map.get("link")}) |\n"
    } else {
        comments +=
                "|  sca  |  [#${BUILD_ID}](${url}) | :warning: 不通过 | [>>>](${map.get("link")}) |\n"
    }
    println("${map.get("link")}")
    println("mapmap:${map}")
    addGitcodeMRComment comment: comments
}

def processResult(result, scaSuccessLabel, scaRunningLabel, scaFailedLabel, unconfirmedFileNum) {
    if (result == "success" && unconfirmedFileNum == 0) {
        println("sca success")
        withCredentials([string(credentialsId: 'opengauss_bot-gitcode-token', variable: 'GITCODE_TOKEN')]) {
            addLabel("${gitcodeTargetNamespace}", "${gitcodeTargetRepoName}", "${gitcodePullRequestIid}", scaSuccessLabel, "${GITCODE_TOKEN}")
            deleteLabel("${gitcodeTargetNamespace}", "${gitcodeTargetRepoName}", "${gitcodePullRequestIid}", scaRunningLabel, "${GITCODE_TOKEN}")
            deleteLabel("${gitcodeTargetNamespace}", "${gitcodeTargetRepoName}", "${gitcodePullRequestIid}", scaFailedLabel, "${GITCODE_TOKEN}")
        }
    } else {
        println("sca failed")
        withCredentials([string(credentialsId: 'opengauss_bot-gitcode-token', variable: 'GITCODE_TOKEN')]) {
            addLabel("${gitcodeTargetNamespace}", "${gitcodeTargetRepoName}", "${gitcodePullRequestIid}", scaFailedLabel, "${GITCODE_TOKEN}")
            deleteLabel("${gitcodeTargetNamespace}", "${gitcodeTargetRepoName}", "${gitcodePullRequestIid}", scaRunningLabel, "${GITCODE_TOKEN}")
            deleteLabel("${gitcodeTargetNamespace}", "${gitcodeTargetRepoName}", "${gitcodePullRequestIid}", scaSuccessLabel, "${GITCODE_TOKEN}")
        }
    }
}

// 使用 @NonCPS 注解避免CPS方法不匹配错误
@NonCPS
def parsePythonOutput(String output) {
    if (output == null || output.isEmpty()) {
        println("Python output is empty")
        return ['status': 'null', 'link': '']
    }
    
    def result = 'null'
    def link = ''
    def state = ''
    def unconfirmedFileNum = 0
    
    // 使用传统的split方式代替eachLine
    def lines = output.split('\n')
    for (line in lines) {
        line = line.trim()
        println(line)
        if (line.startsWith("FINAL_RESULT:")) {
            result = line.substring("FINAL_RESULT:".length()).trim()
            println("Found FINAL_RESULT: ${result}")
        } else if (line.startsWith("FINAL_REPORT_URL:")) {
            link = line.substring("FINAL_REPORT_URL:".length()).trim()
            println("Found FINAL_REPORT_URL: ${link}")
        } else if (line.startsWith("SCA_STATE:")) {
            state = line.substring("SCA_STATE:".length()).trim()
            println("Found SCA_STATE: ${state}")
        } else if (line.startsWith("SCA_UNCONFIRMED_NUM:")) {
            unconfirmedFileNum = line.substring("SCA_UNCONFIRMED_NUM:".length()).trim().toInteger()
            println("Found SCA_UNCONFIRMED_NUM: ${unconfirmedFileNum}")
        } else if (line.startsWith("CREATE_TASK_STATUS:") || 
                   line.startsWith("CREATE_TASK_RESPONSE:") ||
                   line.startsWith("QUERY_STATUS:")) {
            println("[Python Debug] ${line}")
        } else if (line.startsWith("ERROR:") || line.startsWith("CREATE_TASK_ERROR:") || 
                   line.startsWith("CREATE_TASK_EXCEPTION:") || line.startsWith("QUERY_EXCEPTION:")) {
            println("[Python ERROR] ${line}")
        }
    }
    
    if (result == 'null') {
        println("Failed to parse Python output")
        return ['status': 'null', 'link': '']
    }
    
    return ['status': result, 'link': link, 'state': state, 'unconfirmedFileNum': unconfirmedFileNum]
}

def scaFromOpenLibing(String OWNER, String REPO, String NUMBER, String GITCODE_TOKEN, 
                      String CREATE_TASK_AK, String CREATE_TASK_SK,
                      String GET_RESULT_AK, String GET_RESULT_SK) {
    
    if (!(OWNER?.trim() && REPO?.trim() && NUMBER?.trim()))  {
        throw new Exception("any of 'OWNER', 'REPO', 'NUMBER' should not be empty")
    }
    
    println "start sca task with Python SDK"
    
    try {
        def prUrl = "https://gitcode.com/${OWNER}/${REPO}/pull/${NUMBER}"
        println("prUrl: ${prUrl}")
        
        def pythonPath = "/usr/bin/python3"
        def scriptPath = "/data/scacheck/sca_check.py"
        
        // 构建命令 - 使用正确的PYTHONPATH
        //def cmd = """export PYTHONPATH=/data/scacheck/apig && ${pythonPath} ${scriptPath} \
        //    '${CREATE_TASK_AK}' '${CREATE_TASK_SK}' '${GET_RESULT_AK}' '${GET_RESULT_SK}' '${prUrl}'"""
        println "export PYTHONPATH=/data/scacheck/apig && python3 /data/scacheck/sca_check.py --repository_name ${REPO} --pr_id ${NUMBER} --pr_scan_access_key  ${CREATE_TASK_AK} --pr_scan_secret_key ${CREATE_TASK_SK}  --pr_result_access_key ${GET_RESULT_AK} --pr_result_secret_key ${GET_RESULT_SK} --access_token=00"
        def cmd = "export PYTHONPATH=/data/scacheck/apig && python3 /data/scacheck/sca_check.py --repository_name ${REPO} --pr_id ${NUMBER} --pr_scan_access_key  ${CREATE_TASK_AK} --pr_scan_secret_key ${CREATE_TASK_SK}  --pr_result_access_key ${GET_RESULT_AK} --pr_result_secret_key ${GET_RESULT_SK} --access_token=00"
        println("Executing Python script...")
        
        // 执行Python脚本并获取输出
        def output = sh(script: cmd, returnStdout: true).trim()
        
        println("Python script output:\n${output}")
        
        // 解析输出
        def resultMap = parsePythonOutput(output)
        
        return resultMap
        
    } catch(Exception ex) {
        println("failed to sca codecheck: ${ex.getMessage()}")
        println("Exception details: ${ex.toString()}")
        return ['status': 'null', 'link': '']
    }
}

pipeline {
    agent {
        node {
            label "CentOS-build || openEuler-build-01 || openEuler-build-02"
        }
    }
    
    environment {
        def jobName = "openGauss_sca_PR"
        def scaFailedLabel = "sca-failed"
        def scaSuccessLabel = "sca-success"
        def scaRunningLabel = "sca-running"
    }

    stages {
        stage('Init') {
            steps {
                script {
                    echo "gitcodeTargetNamespace ${gitcodeTargetNamespace}"
                    echo "gitcodeTargetRepoName ${gitcodeTargetRepoName}"
                    echo "gitcodePullRequestIid ${gitcodePullRequestIid}"
                    echo "BUILD_ID ${BUILD_ID}"
                }
            }
        }

        stage('sca_pipline') {
            steps {
                script {
                    withCredentials([
                        string(credentialsId: 'create_task_access_key', variable: 'CREATE_TASK_AK'),
                        string(credentialsId: 'create_task_secret_key', variable: 'CREATE_TASK_SK'),
                        string(credentialsId: 'get_result_access_key', variable: 'GET_RESULT_AK'),
                        string(credentialsId: 'get_result_secret_key', variable: 'GET_RESULT_SK'),
                        string(credentialsId: 'opengauss_bot-gitcode-token', variable: 'GITCODE_TOKEN')
                    ]) {
                        def resultMap = scaFromOpenLibing(
                            "${gitcodeTargetNamespace}", 
                            "${gitcodeTargetRepoName}", 
                            "${gitcodePullRequestIid}", 
                            "${GITCODE_TOKEN}",
                            "${CREATE_TASK_AK}", 
                            "${CREATE_TASK_SK}",
                            "${GET_RESULT_AK}",
                            "${GET_RESULT_SK}"
                        )
                        
                        println("Final resultMap: ${resultMap}")
                        
                        def serializedMap = groovy.json.JsonOutput.toJson(resultMap)
                        writeFile file: 'resultMap.json', text: serializedMap
                    }
                }
            }
        }
    }

    post {
        success {
            script {
                retry(3) {
                    echo "-------------------post success-------------------"
                    
                    if (fileExists('resultMap.json')) {
                        def serializedMap = readFile file: 'resultMap.json'
                        def resultMap = new JsonSlurperClassic().parseText(serializedMap)
                        
                        printComments(resultMap, jobName)
                        
                        def unconfirmedFileNum = resultMap.get('unconfirmedFileNum') ?: 0
                        def checkState = resultMap.get('state') ?: "failed"
                        
                        println("unconfirmedFileNum: ${unconfirmedFileNum}")
                        println("state: ${checkState}")
                        
                        withCredentials([string(credentialsId: 'opengauss_bot-gitcode-token', variable: 'GITCODE_TOKEN')]) {
                            processResult(checkState, scaSuccessLabel, scaRunningLabel, scaFailedLabel, unconfirmedFileNum)
                        }
                        
                        sh "rm -f resultMap.json"
                    }
                }
            }
        }
        unsuccessful {
            script {
                retry(3) {
                    echo "-------------------post failed-------------------"
                    
                    if (fileExists('resultMap.json')) {
                        def serializedMap = readFile file: 'resultMap.json'
                        def resultMap = new JsonSlurperClassic().parseText(serializedMap)
                        
                        printComments(resultMap, jobName)
                        
                        def unconfirmedFileNum = resultMap.get('unconfirmedFileNum') ?: 0
                        def checkState = resultMap.get('state') ?: "failed"
                        
                        withCredentials([string(credentialsId: 'opengauss_bot-gitcode-token', variable: 'GITCODE_TOKEN')]) {
                            processResult(checkState, scaSuccessLabel, scaRunningLabel, scaFailedLabel, unconfirmedFileNum)
                        }
                        
                        sh "rm -f resultMap.json"
                    } else {
                        echo "No resultMap.json found, skipping"
                    }
                }
            }
        }
    }
}