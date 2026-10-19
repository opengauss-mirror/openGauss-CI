
docker_name=opengauss-llt-1.0.0
docker_image_name=opengauss-llt:1.0.0
dockerfile=dockerfile_llt
part_type=A
## build docker images
# git clone
# docker build -t ${docker_image_name} -f ./${dockerfile} .


echo "gitcodePullRequestIid: ${gitcodePullRequestIid}"
echo "gitcodeAfterCommitSha: ${gitcodeAfterCommitSha}"
echo "gitcodeRef: refs/merge-requests/${gitcodePullRequestIid}/merge"

if [ "$(docker ps | grep ${docker_name})" != "" ]; then
	docker kill $docker_name
fi

if [ "$(docker ps -a | grep ${docker_name})" != "" ]; then
    docker rm $docker_name
fi
sync && echo 3>/proc/sys/vm/drop_caches
ipcrm -a

## A 测试套不添加 --network=host， 用例forbid_ddl获取ip在容器内外会有差异。

containerid=`docker run --privileged=true --network=host -d -it -P  -v /etc/localtime:/etc/localtime \
        -e PKG_TYPE=DEBUG -e gitcodePullRequestIid=${gitcodePullRequestIid} \
        -e gitcodeAfterCommitSha=${gitcodeAfterCommitSha} -e PART_TYPE=${part_type} \
        -e gitcodeTargetBranch=${gitcodeTargetBranch} --name ${docker_name} ${docker_image_name}`

[ -n "$containerid" ] || { echo "docker run 失败"; exit 1; }

docker logs -f ${containerid}

# 取容器真实退出码
exit_code=$(docker inspect --format '{{.State.ExitCode}}' ${containerid})
oom=$(docker inspect --format '{{.State.OOMKilled}}' ${containerid})
echo "退出码=$exit_code OOMKilled=$oom"

if [ "$exit_code" -eq 0 ] && [ "$oom" = "false" ]; then
    echo "容器正常退出"
    docker rm ${containerid} >/dev/null
else
    echo "容器异常退出 exit=$exit_code"
    docker rm ${containerid} >/dev/null
    exit 1    # 门禁失败
fi