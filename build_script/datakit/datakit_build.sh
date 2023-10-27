#!/bin/bash
echo "giteePullRequestIid: ${giteePullRequestIid}"
echo "giteeAfterCommitSha: ${giteeAfterCommitSha}"
echo "giteeRef: ${giteeRef}"
git config --global core.compression 0

sync && echo 3>/proc/sys/vm/drop_caches
ipcrm -a

# 本地测试
export giteeTargetBranch=master
export WORKSPACE=/usr1/gauss_jenkins/jenkins/workspace
export workbench_repo=https://gitee.com/opengauss/openGauss-workbench.git
export output_dir=$WORKSPACE/workbench/output
export VERSION=5.1.1

function export_env() {
    export ds_tool_home=/home/dstools
    export M2_HOME=$ds_tool_home/apache-maven-3.6.3
    export JAVA8_HOME=$ds_tool_home/jdk1.8.0_311
    export JAVA11_HOME=$ds_tool_home/jdk-11.0.2
    export JAVA_HOME=$JAVA11_HOME
    export NODE_HOME=/home/dstools/node-v16.15.1-linux-x64
    export PATH=$M2_HOME/bin:$JAVA_HOME/bin:$NODE_HOME/bin:$PATH
}

function download_source_from_gitee() {
    repo=$1
    branch=$2
    target_dir=$3
    echo "download source [${repo}], branch [${branch}]"

    a=0
    flag=0
    while [ $a -lt 3 ]; do
        echo "$a"
        cd ${WORKSPACE} && rm -rf ${target_dir}
        timeout 5m git clone ${repo} -b ${branch} "${WORKSPACE}/${target_dir}"
        if [[ $? == 0 ]]; then
            flag=1
            break
        fi
        a=$(expr $a + 1)
        sleep 10
    done

    if [[ $flag == 0 ]]; then
        echo "clone ${target_dir} failed!"
        exit 1
    fi
}

function download_source() {
    cd ${WORKSPACE}
    download_source_from_gitee ${workbench_repo} ${giteeTargetBranch} workbench
}

function build_pkg() {
    cd ${WORKSPACE}/workbench
    chmod a+x build.sh
    sh build.sh
    if [ $? -ne 0 ]; then
        echo "build openGauss-workbench failed!!!"
        exit 1
    fi
}

function upload() {
    cd ${output_dir}/ || exit 1
    obsutil cp Datakit-${VERSION}.tar.gz obs://opengauss/latest/tools/Datakit/
    sha256sum -b Datakit-${VERSION}.tar.gz >Datakit-${VERSION}.tar.gz.sha256
    obsutil cp Datakit-${VERSION}.tar.gz.sha256 obs://opengauss/latest/tools/Datakit/
}

function main() {
    echo "###### build openGauss-workbench(Datakit) ######"
    download_source
    export_env
    build_pkg
    upload
}

main
