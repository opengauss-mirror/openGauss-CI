#!/bin/bash


export WORKSPACE=/usr1/build/workspace
export openGaussServer_Http_Repo_Url=https://gitcode.com/opengauss/openGauss-server.git
export gitcodeTargetBranch=master

################################ 这些需要根据jenkins传入。。。先验证容器跑fastcheck ################################
# echo "gitcodePullRequestIid: ${gitcodePullRequestIid}"
# echo "gitcodeAfterCommitSha: ${gitcodeAfterCommitSha}"
# echo "gitcodeRef: refs/merge-requests/${gitcodePullRequestIid}/merge"
# git config --global core.compression 0

# sync && echo 3>/proc/sys/vm/drop_caches
# ipcrm -a

if [[ "$gitcodeTargetBranch"x = "dev10"x || "$gitcodeTargetBranch"x = "glt"x  || "$gitcodeTargetBranch"x = "iud_dev"x ]]; then
    echo "skip $gitcodeTargetBranch branch gate"
    exit 0
fi


function prepare_deps() {
    mkdir -p ${WORKSPACE}/dependency/cmake

    if [ "$(uname -m)" = "aarch64" ]; then
        tar -xf /cmake-3.19.5-Linux-aarch64.tar.gz -C ${WORKSPACE}/dependency/cmake/
        mv /data/llt/PrivateBuild_tools/config_cmake_arm.ini /data/llt/PrivateBuild_tools/config_cmake.ini
    else
        tar -xf /cmake-3.19.5-Linux-x86_64.tar.gz -C ${WORKSPACE}/dependency/cmake/
        mv /data/llt/PrivateBuild_tools/config_cmake_x86.ini /data/llt/PrivateBuild_tools/config_cmake.ini
    fi
}

function download_source_from_gitcode() {
    repo=$1
    branch=$2
    target_dir=$3
    echo "download source [${repo}], branch [${branch}]"

    a=0
    flag=0
    while [ $a -lt 3 ]; do
        echo "$a"
        rm -rf ${WORKSPACE}/${target_dir}
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
    download_source_from_gitcode ${openGaussServer_Http_Repo_Url} ${gitcodeTargetBranch} openGauss
}

function merge_source_code() {
    cd ${WORKSPACE}/openGauss
    git config --global user.email "570157209@qq.com"
    git config --global user.name "l1azzzy"
    git rev-parse --is-inside-work-tree
    git config remote.origin.url ${openGaussServer_Http_Repo_Url}
    git fetch origin refs/merge-requests/${gitcodePullRequestIid}/head:refs/merge-requests/${gitcodePullRequestIid}/head
    git merge --no-verify refs/merge-requests/${gitcodePullRequestIid}/head --no-edit
}

function download_binarylibs() {
    cd ${WORKSPACE} && rm -rf openGauss-third_party_binarylibs*

    echo "downing binarylibs--------------------"
    BINARYLIBS_NAME_CENTOS_X86=openGauss-third_party_binarylibs_Centos7.6_x86_64
    BINARYLIBS_NAME_OPENEULER_X86=openGauss-third_party_binarylibs_openEuler_x86_64
    BINARYLIBS_NAME_OPENEULER_ARM=openGauss-third_party_binarylibs_openEuler_arm
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
    if [[ "$gitcodeTargetBranch"x = "master"x ]] && [[ "$binarylibs_file"x = ""x ]]; then
        echo "Not found binarylibs of platfrom: ${os_name}_${cpu_arc}"
        exit 1
    fi
    echo "Build openGauss user third-party_binarylibs: ${binarylibs_file}"

    set -e
    if [[ "$gitcodeTargetBranch"x = "2.0.0"x ]]; then
        wget ftp://192.168.0.9/3rd/gcc7.3/2.0.0/openGauss-third_party_binarylibs.tar.gz -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz -q
    elif [[ "$gitcodeTargetBranch"x = "3.0.0"x ]]; then
        wget ftp://192.168.0.9/3rd/gcc7.3/3.0.0/${binarylibs_file}-3.0.3.tar.gz -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz -q
    elif [[ "$gitcodeTargetBranch"x = "5.0.0"x ]]; then
        wget ftp://192.168.0.9/3rd/gcc7.3/5.0.0/${binarylibs_file}.tar.gz -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz -q
    elif [[ "$gitcodeTargetBranch"x = "5.1.0"x || "$gitcodeTargetBranch"x = "dev_board"x ]]; then
        wget ftp://192.168.0.9/3rd/gcc10.3/5.1.0/${binarylibs_file}.tar.gz -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz -q
    elif [[ "$gitcodeTargetBranch"x = "6.0.0"x || "$gitcodeTargetBranch"x = "6.0.5"x ]]; then
        wget ftp://192.168.0.9/3rd/gcc10.3/6.0.0/${binarylibs_file}.tar.gz -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz -q
    elif [[ "$gitcodeTargetBranch"x = "6.0.0_tag"x || "$gitcodeTargetBranch"x = "tp_poc"x || "$gitcodeTargetBranch"x = "datavec_poc"x ]]; then
        wget ftp://192.168.0.9/3rd/gcc10.3/6.0.0/${binarylibs_file}.tar.gz -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz -q
    elif [[ "$gitcodeTargetBranch"x = "master"x || "$gitcodeTargetBranch"x = "dev"x || "$gitcodeTargetBranch"x = "7.0.0-RC3"x ]]; then
        wget ftp://192.168.0.9/3rd/gcc10.3/master/${binarylibs_file}.tar.gz -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz -q
    elif [[ "$gitcodeTargetBranch"x = "7.0.0-RC1"x ]]; then
        wget ftp://192.168.0.9/3rd/gcc10.3/7.0.0-RC1/${binarylibs_file}.tar.gz -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz -q
    elif [[ "$gitcodeTargetBranch"x = "7.0.0-RC2"x || "$gitcodeTargetBranch"x = "dev"x ]]; then
        wget ftp://192.168.0.9/3rd/gcc10.3/master/${binarylibs_file}.tar.gz -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz -q
    elif [[ "$gitcodeTargetBranch"x = "7.0.0"x ]]; then
        wget ftp://192.168.0.9/3rd/gcc10.3/master/${binarylibs_file}.tar.gz -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz -q
    else
        echo "ERROR: $gitcodeTargetBranch branch not found"
    fi
    set +e

    cd ${WORKSPACE}
    mkdir -p ${WORKSPACE}/openGauss-third_party_binarylibs
    tar -zxf ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz -C openGauss-third_party_binarylibs --strip-components 1
}

function make_fastcheck_single() {
    cd ${WORKSPACE}/openGauss/build/script
    chmod +x build_opengauss.sh
    if [[ $gitcodeTargetBranch = "2.0.0" ]]; then
        sed -i "s/make -sj 8/make -sj16/g" mpp_package.sh
        sed -i "s/make install -sj 8/make install -sj16/g" mpp_package.sh
    else
        sed -i "s/make -sj 20/make -sj16/g" utils/make_compile.sh
        sed -i "s/make install -sj 8/make install -sj16/g" utils/make_compile.sh
    fi

    chmod -R 755 /usr1
    chmod -R 755 /data/llt/PrivateBuild_tools
    chmod -R 755 /data/config

    if [[ $gitcodeTargetBranch = "2.0.0" || $gitcodeTargetBranch = "3.0.0" || $gitcodeTargetBranch = "dev" ]]; then
        # 2.0.0和3.0.0,dev分支，只跑一个文件,不加参数
        sh /data/llt/PrivateBuild_tools/Private_Main.sh 0 ${WORKSPACE}/openGauss
    else
        # 其他分支，跑A B C三个文件
        sh /data/llt/PrivateBuild_tools/Private_Main.sh 0 ${WORKSPACE}/openGauss A
    fi
}

function main() {
    prepare_deps
    download_source
    # merge_source_code
    download_binarylibs
    make_fastcheck_single
}

main "$@"
