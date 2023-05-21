#!/bin/bash
set -x
echo "giteePullRequestIid: ${giteePullRequestIid}"
echo "giteeAfterCommitSha: ${giteeAfterCommitSha}"
echo "giteeRef: ${giteeRef}"
git config --global core.compression 0

sync && echo 3>/proc/sys/vm/drop_caches
ipcrm -a

# 本地测试
giteeTargetBranch=master
WORKSPACE=/usr1/gauss_jenkins/jenkins/workspace
openGaussServer_Http_Repo_Url=https://gitee.com/opengauss/openGauss-server.git

if [[ "$giteeTargetBranch"x = "dev10"x || "$giteeTargetBranch"x = "glt"x ]]; then
    echo "skip $giteeTargetBranch branch gate"
    exit 0
fi

function download_source_from_gitee() {
    repo=$1
    branch=$2
    target_dir=$3
    echo "download source [${repo}], branch [${branch}]"

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
        a=$(expr $a + 1)
    done

    if [[ $flag == 0 ]]; then
        echo "clone ${target_dir} failed!"
        exit 1
    fi
}

function download_source() {
    cd ${WORKSPACE}
    download_source_from_gitee ${openGaussServer_Http_Repo_Url} ${giteeTargetBranch} openGauss
}

function merge_source_code() {
    cd ${WORKSPACE}/openGauss
    git rev-parse --is-inside-work-tree
    git config remote.origin.url ${openGaussServer_Http_Repo_Url}
    git fetch --tags --force --progress origin ${giteeRef}:${giteeRef}
    git checkout -b ${giteeRef} ${giteeRef}
}

function download_binarylibs() {
    cd ${WORKSPACE} && rm -rf openGauss-third_party_binarylibs*

    echo "downing binarylibs--------------------"
    BINARYLIBS_NAME_CENTOS_X86=openGauss-third_party_binarylibs_Centos7.6_x86_64
    BINARYLIBS_NAME_OPENEULER_X86=openGauss-third_party_binarylibs_openEuler_arm
    BINARYLIBS_NAME_OPENEULER_ARM=openGauss-third_party_binarylibs_openEuler_x86_64
    # get 3rd of each platform
    os_name=$(
        source /etc/os-release
        echo $ID
    )
    cpu_arc=$(uname -p)
    binarylibs_file=""
    if [[ "$os_name"x = "centos"x ]] && [[ "$cpu_arc"x = "x86_64"x ]]; then
        binarylibs_file=$BINARYLIBS_NAME_CENTOS_X86
    elif [[ "$os_name"x = "euleros"x ]] && [[ "$cpu_arc"x = "aarch64"x ]]; then
        binarylibs_file=$BINARYLIBS_NAME_OPENEULER_ARM
    elif [[ "$os_name"x = "openEuler"x ]] && [[ "$cpu_arc"x = "aarch64"x ]]; then
        binarylibs_file=$BINARYLIBS_NAME_OPENEULER_ARM
    elif [[ "$os_name"x = "openEuler"x ]] && [[ "$cpu_arc"x = "x86_64"x ]]; then
        binarylibs_file=$BINARYLIBS_NAME_OPENEULER_X86
    elif [[ "$os_name"x = "asianux"x ]] && [[ "$cpu_arc"x = "x86_64"x ]]; then
        binarylibs_file=$BINARYLIBS_NAME_OPENEULER_X86
    elif [[ "$os_name"x = "asianux"x ]] && [[ "$cpu_arc"x = "aarch64"x ]]; then
        binarylibs_file=$BINARYLIBS_NAME_OPENEULER_ARM
    else
        echo "Not support this platfrom: ${os_name}_${cpu_arc}"
        exit 1
    fi
    if [[ "$giteeTargetBranch"x = "master"x ]] && [[ "$binarylibs_file"x = ""x ]]; then
        echo "Not found binarylibs of platfrom: ${os_name}_${cpu_arc}"
        exit 1
    fi
    echo "Build openGauss user third-party_binarylibs: ${binarylibs_file}"

    set -e
    if [[ "$giteeTargetBranch"x = "2.0.0"x ]]; then
        wget https://opengauss.obs.cn-south-1.myhuaweicloud.com/2.0.0/binarylibs/${binarylibs_file}.tar.gz -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz
    elif [[ "$giteeTargetBranch"x = "3.0.0"x ]]; then
        wget https://opengauss.obs.cn-south-1.myhuaweicloud.com/3.0.0/binarylibs/${binarylibs_file}.tar.gz -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz
    elif [[ "$giteeTargetBranch"x = "5.0.0"x ]]; then
        wget https://opengauss.obs.cn-south-1.myhuaweicloud.com/5.0.0/binarylibs/${binarylibs_file}.tar.gz -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz
    elif [[ "$giteeTargetBranch"x = "master"x ]]; then
        wget https://opengauss.obs.cn-south-1.myhuaweicloud.com/latest/binarylibs/${binarylibs_file}.tar.gz -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz
    else
        echo "ERROR: $giteeTargetBranch branch not found"
    fi
    set +e

    cd ${WORKSPACE}
    mkdir -p ${WORKSPACE}/openGauss-third_party_binarylibs
    tar -zxf ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz -C openGauss-third_party_binarylibs --strip-components 1
}

function pkg() {
    # 打包工程
    cd /usr/bin
    rm -rf python
    ln -sf python2 python

    cd ${WORKSPACE}/openGauss/build/script
    chmod +x build_opengauss.sh

    if [[ $giteeTargetBranch = "2.0.0" ]]; then
        chmod +x build_opengauss.sh
        sed -i "s/make -sj 8/make -sj16/g" mpp_package.sh
        sed -i "s/make install -sj 8/make install -sj16/g" mpp_package.sh
    else
        sed -i "s/make -sj 20/make -sj16/g" utils/make_compile.sh
        sed -i "s/make install -sj 8/make install -sj16/g" utils/make_compile.sh
    fi

    cd ${WORKSPACE}/openGauss
    sh build.sh -m release -3rd ${WORKSPACE}/openGauss-third_party_binarylibs -pkg

    cd ${WORKSPACE}/OM
    sh build.sh -3rd ${WORKSPACE}/openGauss-third_party_binarylibs
    # copy om包
    cp ${WORKSPACE}/OM/package/*om.tar.gz ${WORKSPACE}/openGauss/output/.
}

function install_upgrade() {
    # 执行om ##
    cd /usr/bin
    rm -rf python
    ln -sf python3 python
    cd /home/OM

    export LD_LIBRARY_PATH=${WORKSPACE}/om/package/script/gspylib/clib:$LD_LIBRARY_PATH

    pkg_branch="2.1.0"
    if [ "${giteeTargetBranch}"x == "master"x ]; then
        pkg_branch="5.1.0"
    elif [ "${giteeTargetBranch}"x == "3.0.0"x ]; then
        pkg_branch="3.0.3"
    elif [ "${giteeTargetBranch}"x == "dev"x ]; then
        pkg_branch="3.0.0"
    elif [ "${giteeTargetBranch}"x == "2.0.0"x ]; then
        pkg_branch="2.0.5"
    elif [ "${giteeTargetBranch}"x == "dev"x ]; then
        pkg_branch="3.0.0"
    else
        pkg_branch=$giteeTargetBranch
    fi

    echo "pakcage version is: $pkg_branch"

    # 安装
    sh automated-test.sh ${WORKSPACE} ${pkg_branch}

    #升级(基础包未传入)
    sh auto_upgradectl.sh ${WORKSPACE} ${pkg_branch}

    if [ -e /home/OM/ssh/known_hosts ]; then
        rm -rf ~/.ssh/*
        cp /home/OM/ssh/* ~/.ssh/
    fi
}

function main() {
    download_source
    merge_source_code
    download_binarylibs
    pkg
    install_upgrade
}

main "$@"
