#!/bin/bash
set -x
#本地测试
WORKSPACE=/data/autobuild
giteeTargetBranch=master
dbMind_repo=https://gitee.com/opengauss/openGauss-DBMind.git
obs_upload_path=obs://opengauss/latest/dbmind

function down_soure_from_gitee() {
    repo=$1
    branch=$2
    target_dir=$3

    a=0
    flag=0
    while [ $a -lt 3 ]; do
        echo "$a"
        rm -rf ${WORKSPACE}/${target_dir}
        timeout 120 git clone ${repo} -b ${branch} "${WORKSPACE}/${target_dir}"
        if [[ $? == 0 ]]; then
            flag=1
            break
        fi
        a=$(expr "$a" + 1)
    done

    if [[ $flag = 0 ]]; then
        echo "clone ${target_dir} failed!"
        exit 1
    fi
}

function down_source() {
    down_soure_from_gitee ${dbMind_repo} ${giteeTargetBranch} dbmind
}

function merge_source_code() {
    cd ${WORKSPACE}/dbmind
    git rev-parse --is-inside-work-tree
    git config remote.origin.url ${dbMind_repo}
    git fetch --tags --force --progress origin ${giteeRef}:${giteeRef}
    git checkout -b ${giteeRef} ${giteeRef}
}

function package() {
    cd ${WORKSPACE}/dbmind
    sh package.sh
    if [[ $? == 0 ]]; then
        echo "dbmind package success."
    else
        echo "dbmind package failed."
        exit 1
    fi
    # dbmind打包
    arch=$(uname -m)
    tar -zcf dbmind-installer-${arch}-python3.10.sh.tar.gz dbmind-installer-${arch}-python3.10.sh
}

function uplod_package() {
    arch=$(uname -m)
    if [ "X$arch" == "Xaarch64" ]; then
        dbs_dest="arm"
    else
        if [ -f "/etc/openEuler-release" ]; then
            dbs_dest="x86_openEuler"
        else
            dbs_dest="x86"
        fi
    fi

    # 判断是否在支持的系统中
    kernel=""
    version=""
    ext_version=""
    dist_version=""
    if [ -f "/etc/euleros-release" ]; then
        kernel=$(cat /etc/euleros-release | awk -F ' ' '{print $1}' | tr A-Z a-z)
        version=$(cat /etc/euleros-release | awk -F '(' '{print $2}' | awk -F ')' '{print $1}' | tr A-Z a-z)
        ext_version=$version
    elif [ -f "/etc/openEuler-release" ]; then
        kernel=$(cat /etc/openEuler-release | awk -F ' ' '{print $1}' | tr A-Z a-z)
        version=$(cat /etc/openEuler-release | awk -F '(' '{print $2}' | awk -F ')' '{print $1}' | tr A-Z a-z)
    elif [ -f "/etc/centos-release" ]; then
        kernel=$(cat /etc/centos-release | awk -F ' ' '{print $1}' | tr A-Z a-z)
        version=$(cat /etc/centos-release | awk -F '(' '{print $2}' | awk -F ')' '{print $1}' | tr A-Z a-z)
    else
        kernel=$(lsb_release -d | awk -F ' ' '{print $2}' | tr A-Z a-z)
        version=$(lsb_release -r | awk -F ' ' '{print $2}')
    fi

    if [ X"$kernel" == X"euleros" ]; then
        dist_version="EULER"
    elif [ X"$kernel" == X"centos" ]; then
        dist_version="CentOS"
    elif [ X"$kernel" == X"openeuler" ]; then
        dist_version="openEuler"
    else
        echo "Only support EulerOS|Centos|openEuler platform."
        echo "Kernel is $kernel"
        exit 1
    fi

    local upload_log=upload.log
    local upload_1_log=upload_1.log
    rm -rf ${upload_log}
    rm -rf ${upload_1_log}

    package_list=$(ls *.tar.gz | grep "dbmind" | xargs -n 1 basename)
    package_num=$(ls *.tar.gz | grep "dbmind" | wc -l)
    for package_name in ${package_list[@]}; do
        sha256sum -b $package_name >$package_name.sha256
        push_command1="/home/obsutil cp ${package_name} ${obs_upload_path}/${dbs_dest}/"
        push_command2="/home/obsutil cp ${package_name}.sha256 ${obs_upload_path}/${dbs_dest}/"
        set +e
        $push_command1 | tee -a $upload_log
        $push_command2 | tee -a $upload_log
    done

    if [ -f $upload_log ]; then
        # 值为1表示编译成功
        is_uload_package_success=$(grep "Upload successfully" $upload_log | wc -l)
        if [ $is_uload_package_success -eq $((package_num * 2)) ]; then
            echo 'info' 'upload package to obs successfully '
        else
            echo 'error' 'upload package to obs failed'
            exit 1
        fi
    else
        echo 'error' 'not generate upload.log upload package to obs failed'
        exit 1
    fi
}

function main() {
    down_source
    package
    uplod_package
}

main "$@"
