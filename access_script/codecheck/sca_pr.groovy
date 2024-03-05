import groovy.json.JsonSlurperClassic
import javax.crypto.spec.SecretKeySpec
import javax.crypto.Mac
import java.security.NoSuchAlgorithmException
import java.security.InvalidKeyException

def deleteLabel(namespace, repo, prNumber, label, token) {
    println("Delete labels")

    def requestUrl = 'https://gitee.com/api/v5/repos/' + namespace + '/' + repo + "/pulls/" + prNumber + "/labels/" + label
    println requestUrl
    def auth_token = "Authorization: Bearer " + token
    def header = "Content-Type: application/json;charset=UTF-8"
    response = sh(script: "curl -X DELETE $requestUrl -H '$auth_token' -H '$header'", returnStdout: true).trim()

    println("delete ${label} success")
}

def addLabel(namespace, repo, prNumber, label, token) {
    println("Delete ${label} labels")

    def requestUrl = "https://gitee.com/api/v5/repos/" + namespace + "/" + repo + "/pulls/" + prNumber + "/labels"
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

    addGiteeMRComment comment: comments
}

def processResult(checkState, scaSuccessLabel, scaRunningLabel, scaFailedLabel) {
    if (checkState == "success") {
        println("sca success")
        withCredentials([string(credentialsId: 'gitee_token_id', variable: 'GITEE_TOKEN')]) {
            addLabel("${giteeTargetNamespace}", "${giteeTargetRepoName}", "${giteePullRequestIid}", scaSuccessLabel, "${GITEE_TOKEN}")
            deleteLabel("${giteeTargetNamespace}", "${giteeTargetRepoName}", "${giteePullRequestIid}", scaRunningLabel, "${GITEE_TOKEN}")
        }
    } else {
        println("sca failed")
        withCredentials([string(credentialsId: 'gitee_token_id', variable: 'GITEE_TOKEN')]) {
            addLabel("${giteeTargetNamespace}", "${giteeTargetRepoName}", "${giteePullRequestIid}", scaFailedLabel, "${GITEE_TOKEN}")
            deleteLabel("${giteeTargetNamespace}", "${giteeTargetRepoName}", "${giteePullRequestIid}", scaRunningLabel, "${GITEE_TOKEN}")
        }
    }
}

def getBase64HmacSHA256(secretKey, data) {
    try {
        SecretKeySpec key = new SecretKeySpec(secretKey.getBytes(), "HmacSHA256")
        Mac hmac = Mac.getInstance("HmacSHA256")
        hmac.init(key)
        byte[] signBytes = hmac.doFinal(data.getBytes())
        return Base64.getEncoder().encodeToString(signBytes)
    } catch (NoSuchAlgorithmException | InvalidKeyException | IllegalArgumentException e) {
        println(e.getMessage())
    }
    return ""
}

def scaFromOpenLibing(String OWNER, String REPO, String NUMBER, String appId, String secretKey) {
    if (!(OWNER?.trim() && REPO?.trim() && NUMBER?.trim())) {
        throw new Exception("any of 'OWNER', 'REPO', 'NUMBER' should not be empty")
    }
    def timestamp = String.valueOf(System.currentTimeMillis())
    def message = appId + timestamp
    def sign = getBase64HmacSHA256(secretKey, message)
    println "start sca task"
    try {
        def prUrl = "https://gitee.com/${OWNER}/${REPO}/pulls/${NUMBER}"
        def data = [
                "prUrl"       : prUrl,
                "privateToken": ""
        ]
        println prUrl
        def jsonbody = groovy.json.JsonOutput.toJson(data)
        def scaUrl = "https://sca.osinfra.cn/gateway/dm-service/scan/pr"
        def response = httpRequest acceptType: 'APPLICATION_JSON', contentType: 'APPLICATION_JSON',
                customHeaders: [
                        [maskValue: true, name: 'appId', value: appId],
                        [maskValue: true, name: 'timestamp', value: timestamp],
                        [maskValue: true, name: 'sign', value: sign]
                ],
                requestBody: jsonbody,
                httpMode: 'POST',
                quiet: true,
                ignoreSslErrors: true,
                timeout: 60,
                url: scaUrl,
                validResponseCodes: '200,505', validResponseContent: 'data';
        if (response.status != 200) {
            println("[ERROR] get token rest api error, recheck sca codecheck")
            sleep(3)
            response = httpRequest acceptType: 'APPLICATION_JSON', contentType: 'APPLICATION_JSON',
                    customHeaders: [
                            [maskValue: true, name: 'appId', value: appId],
                            [maskValue: true, name: 'timestamp', value: timestamp],
                            [maskValue: true, name: 'sign', value: sign]
                    ],
                    requestBody: jsonbody,
                    httpMode: 'POST',
                    quiet: true,
                    ignoreSslErrors: true,
                    timeout: 60,
                    url: scaUrl,
                    validResponseCodes: '200,505', validResponseContent: 'data'
            if (response.status != 200) {
                if (sca_result.status == 41000) {
                    sleep(5)
                    println("[WARNING] prUrl is error,please check  prUrl.......")
                    return ['status': 'null', 'link': '']
                }
                if (sca_result.status == 41001) {
                    sleep(5)
                    println("[WARNING] Do not repeat access,please  wait a minute.......")
                    return ['status': 'null', 'link': '']
                }
                println("[ERROR] get sca task id error, skip sca codecheck")
                return ['status': 'null', 'link': '']
            }
        }
        println(response.content)
        def sca_response_content = new JsonSlurperClassic().parseText(response.content)
        println "get sca task id succ"
        def task_id = sca_response_content['data']
        def scarUrl = "https://sca.osinfra.cn/gateway/dm-service/scan/result?scanId=${task_id}"
        for (int tmpi = 0; tmpi < 30; tmpi++) {
            try {
                def get_result_timestamp = String.valueOf(System.currentTimeMillis())
                def get_result_message = appId + get_result_timestamp
                def reulst_sign = getBase64HmacSHA256(secretKey, get_result_message)
                sresponse = httpRequest acceptType: 'APPLICATION_JSON', contentType: 'APPLICATION_JSON',
                        customHeaders: [
                                [maskValue: true, name: 'appId', value: appId],
                                [maskValue: true, name: 'timestamp', value: get_result_timestamp],
                                [maskValue: true, name: 'sign', value: reulst_sign]
                        ],
                        httpMode: 'GET',
                        quiet: true,
                        ignoreSslErrors: true,
                        timeout: 60,
                        url: scarUrl,
                        validResponseCodes: '200,505', validResponseContent: 'data'
                if (sresponse.status == 200) {
                    sca_result_content = new JsonSlurperClassic().parseText(sresponse.content)

                    println "get sca task id $task_id suc, reuslt is $sca_result_content"
                    sca_result = sca_result_content['data']
                    result_url = sca_result.prResult
                    result = sca_result.state
                    if (result == "success" || result == "failure") {
                        println "get sca task id suc result,$sca_result"
                        println "get sca task id suc result,$result"
                        println "get sca task id suc result_url,$result_url"
                        if (result == "success") {
                            return ['status': 'pass', 'link': result_url]
                        } else {
                            return ['status': 'no pass', 'link': result_url]
                        }
                    } else {
                        sleep(10)
                        println("[WARNING] recheck sca.......")
                        continue
                    }

                } else {
                    if (sca_result.status == 500) {
                        sleep(5)
                        println("[WARNING] server error, recheck.......")
                        continue
                    }

                    println("[ERROR] rest api error, skip sca codecheck")
                    return ['status': 'null', 'link': '']
                }
            } catch (Exception ex11) {
                println "failed to codecheck, $ex11"
                println("[WARNING] server error, recheck.......")
                sleep(5)
                continue
            }

        }
        println("[ERROR] sca check timeout!!")
        return ['status': 'timeout', 'link': '']
    } catch (Exception ex) {
        println "failed to sca codecheck, $ex"
    }
}

pipeline {
    agent {
        node {
            label "x86-build"
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
                    echo "giteeTargetNamespace ${giteeTargetNamespace}"
                    echo "giteeTargetRepoName ${giteeTargetRepoName}"
                    echo "giteePullRequestIid ${giteePullRequestIid}"
                    echo "BUILD_ID ${BUILD_ID}"

                    def resultMap = [:]

                }
            }
        }

        stage('sca_pipline') {
            steps {
                withCredentials([string(credentialsId: 'appId', variable: 'appId'), string(credentialsId: 'secretKey', variable: 'secretKey')]) {
                    script {
                        resultMap = scaFromOpenLibing("${giteeTargetNamespace}", "${giteeTargetRepoName}", "${giteePullRequestIid}", "${appId}", "${secretKey}")
                        println("resultMap" + "${resultMap}")
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
                    // 输出评论
                    printComments(resultMap, jobName)
                }
            }
        }
        unsuccessful {
            script {
                retry(3) {
                    echo "-------------------post failed-------------------"
                    printComments(resultMap, jobName)
                }
            }
        }
    }
}