
docker_name=opengauss-ss_hatest-1.0.0
docker_image_name=opengauss-ss_hatest:1.0.0
dockerfile=dockerfile_ss_hatest
## build docker images

echo "gitcodePullRequestIid: ${gitcodePullRequestIid}"
echo "gitcodeAfterCommitSha: ${gitcodeAfterCommitSha}"
echo "gitcodeRef: refs/merge-requests/${gitcodePullRequestIid}/merge"

## run docker images
if [ "$(docker ps -a | grep ${docker_name})" != "" ]; then
    docker kill $docker_name
    docker rm $docker_name
fi

containerid=`docker run --sysctl kernel.sem="250 6400000 1000 25600" --privileged=true --network=host -d -it -P  -v /etc/localtime:/etc/localtime \
        -e PKG_TYPE=DEBUG -e gitcodePullRequestIid=${gitcodePullRequestIid} \
        -e gitcodeAfterCommitSha=${gitcodeAfterCommitSha} \
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
