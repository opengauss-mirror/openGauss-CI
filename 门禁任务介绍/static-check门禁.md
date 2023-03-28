# static-check门禁介绍

目前static-check任务主要有codecheck和scanosscheck两个任务



## codecheck门禁

codecheck门禁的作用是代码检查

在进行codecheck之前，首先确保环境中有python3，并且有request模块

1. codecheck本地机器发送请求到远端平台

```sh
#  seed 此时发送请求的时间，目的是为了给每个结果文件加个日期保证每个文件唯一，不会被其他线程影响
python3 /data/codecheck_request.py --pull-id=${pr_id} --repo-url=${repo_url} --seed=${seed}
```

2. 远端平台接受到请求，处理后将结果返回给codecheck本地机器

```python
// 远端平台将结果，写到本地机器的两个文件中，result_file,state_file
// result_file 放的是一个连接，这个链接记录结果的详细信息
// state_file 记录的是检查通过是否的标志 success failed
url = result.get("url")
with open(self.result_file, "w+") as fd:
    fd.write(url)
    if result.get("state") != RESULT_FAILED:
        with open(self.state_file, "w+") as fd:
            fd.write("success")
     else:
         with open(self.state_file, "w+") as fd:
             fd.write("failed")
```

3. 查询结果，来判断是否codecheck是否通过

```shell
checkResult = readFile(result_file)
println(checkResult)
checkState = readFile(state_file)
println(checkState)
```



## scanoss门禁

scanoss门禁的作用是开源引用扫描，并且scanoss通过插件来管理

1. scanoss通过sca插件发送请求

```shell
# url：发送请求的地址  sbomFile：一个json文件，用于配置白名单，在白名单上面的项目不进行扫描
sca authCode: '', credentialsId: '', method: 'WebHook', methodChoose: '', sbomFile: '/data/black.json', scanossCredentials: '', sourceFile: '', sudoOrder: 'sudo', url: '', urlChoose: '1'
```

2. 远端将结果返回，读取结果

```groovy
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
```

