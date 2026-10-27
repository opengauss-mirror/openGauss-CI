
docker_name=opengauss-ss-2.0.0
docker_image_name=opengauss-ss:2.0.0
dockerfile=dockerfile_ss

## runner共享池，共享磁盘放三方库
shared_disk_mount_path=/sharedir/

echo "gitcodePullRequestIid: ${gitcodePullRequestIid}"
echo "gitcodeAfterCommitSha: ${gitcodeAfterCommitSha}"
echo "gitcodeRef: refs/merge-requests/${gitcodePullRequestIid}/merge"

## 强杀同名容器
if [ "$(docker ps | grep ${docker_name})" != "" ]; then
	docker kill $docker_name
fi

## 删除历史已经退出的容器
if [ "$(docker ps -a | grep Exited)" != "" ]; then
    docker rm `docker ps -a | grep Exited |awk '{print $1}'`
fi
# sync && echo 3>/proc/sys/vm/drop_caches
# ipcrm -a

containerid=`docker run --sysctl kernel.sem="250 6400000 1000 25600" --privileged=true --network=host -d -it -P  -v /etc/localtime:/etc/localtime -v ${shared_disk_mount_path}:/mnt/ \
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
