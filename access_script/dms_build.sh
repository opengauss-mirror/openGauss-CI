#!/bin/bash
set -euxo pipefail
echo "giteePullRequestIid: ${giteePullRequestIid}"
echo "giteeAfterCommitSha: ${giteeAfterCommitSha}"
echo "giteeRef: ${giteeRef}"
git config --global core.compression 0

sync && echo 3 > /proc/sys/vm/drop_caches
ipcrm -a

DMS_GITEE_REPO=https://gitee.com/opengauss/DMS.git
CBB_GITEE_REPO=https://gitee.com/opengauss/CBB.git
third_party_binarylibs_path=${WORKSPACE}/openGauss-third_party_binarylibs
third_party_binarylibs_package=xxxx

function down_soure_from_gitee() {
    repo=$1
    branch=$2
    target_dir=$3

    a=0
    flag=0
    while [ $a -lt 10 ]; do
        echo $a
        rm -rf ${WORKSPACE}/${target_dir}
        timeout 120 git clone ${repo} -b ${branch} "${WORKSPACE}/${target_dir}"
        if [[ $? == 0 ]]; then
            flag=1
            break
        fi
        a=$(expr $a + 1)
    done

    if [[ $flag = 0 ]]; then
        echo "clone ${target_dir} failed!"
        exit 1
    fi
}

function down_binarylibs() {
    echo "downing binarylibs"
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
    elif [[ "$os_name"x = "ubuntu"x ]] && [[ "$cpu_arc"x = "x86_64"x ]]; then
        binarylibs_file=""
    elif [[ "$os_name"x = "asianux"x ]] && [[ "$cpu_arc"x = "x86_64"x ]]; then
        binarylibs_file=$BINARYLIBS_NAME_CENTOS_X86
    elif [[ "$os_name"x = "asianux"x ]] && [[ "$cpu_arc"x = "aarch64"x ]]; then
        binarylibs_file=$BINARYLIBS_NAME_OPENEULER_ARM
    else
        echo "Not support this platfrom: $os_name_$cpu_arc"
        exit 1
    fi
    if [[ $giteeTargetBranch = "master" ]] && [[ "${binarylibs_file}" = "" ]]; then
        echo "Not found binarylibs of platfrom: $os_name_$cpu_arc"
        exit 1
    fi
    echo "Build openGauss user third-party_binarylibs: ${binarylibs_file}"

    # delete old 3rd
    rm -rf ${WORKSPACE}/openGauss-third_party_binarylibs*
    if [[ $giteeTargetBranch = "2.0.0" ]]; then
        wget -q -P ${WORKSPACE} ${third_party_binarylibs_package} -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz
    elif [[ $giteeTargetBranch = "3.0.0" ]]; then
        echo "user 3.0.0 version 3rd binarylibs"
        wget -q -P ${WORKSPACE} ${third_party_binarylibs_package} -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz
    else
        wget -q -P ${WORKSPACE} ${third_party_binarylibs_package} -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz
    fi

    cd ${WORKSPACE}
    mkdir -p ${WORKSPACE}/openGauss-third_party_binarylibs
    tar -zxf ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz -C openGauss-third_party_binarylibs --strip-components 1
}

function compile() {
    export PATH=/usr/local/cmake/cmake-3.19.5-Linux-x86_64/bin:$PATH

    echo "Start to build CBB..."
    cd ${WORKSPACE}/CBB/build/linux/opengauss
    sh -x build.sh -3rd ${third_party_binarylibs_path} -m Release -t cmake

    echo "Start to build DMS..."
    cd ${WORKSPACE}/DMS/build/linux/opengauss
    sh -x build.sh -3rd ${third_party_binarylibs_path} -m Release -t cmake

    if [[ $? == 0 ]]; then
        echo "DMS build success."
    else
        echo "DMS build failed."
        exit 1
    fi
}

function down_source() {
    down_soure_from_gitee ${DMS_GITEE_REPO} ${giteeTargetBranch} DMS
    down_soure_from_gitee ${CBB_GITEE_REPO} ${giteeTargetBranch} CBB
}

function merge_source_code() {
    cd ${WORKSPACE}/DMS
    git rev-parse --is-inside-work-tree
    git config remote.origin.url ${DMS_GITEE_REPO}
    git fetch --tags --force --progress origin ${giteeRef}:${giteeRef}
    git checkout -b ${giteeRef} ${giteeRef}
}

function main() {
    down_source
    merge_source_code
    down_binarylibs
    compile
}

main
