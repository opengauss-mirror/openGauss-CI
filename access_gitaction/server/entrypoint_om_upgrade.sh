#!/bin/bash


# 本地测试
export gitcodeTargetBranch=master
export openGaussServer_Http_Repo_Url=https://gitcode.com/opengauss/openGauss-server.git

export WORKSPACE=/usr1/build/workspace


#!/bin/bash

echo "gitcodeTargetBranch: ${gitcodeTargetBranch}"
echo "gitcodePullRequestIid: ${gitcodePullRequestIid}"
echo "gitcodeAfterCommitSha: ${gitcodeAfterCommitSha}"
echo "gitcodeRef: ${gitcodeMergeRef}"
git config --global core.compression 0

#开发板版本为5.1.0
if [[ "$gitcodeTargetBranch"x = "dev_board"x ]]; then
    gitcodeTargetBranch="5.1.0"
fi
sync && echo 3>/proc/sys/vm/drop_caches
ipcrm -a

# 本地测试
gitcodeTargetBranch=master
WORKSPACE=/usr1/build/workspace
openGaussServer_Http_Repo_Url=https://gitcode.com/opengauss/openGauss-server.git
om_repo=https://gitcode.com/opengauss/openGauss-OM.git
openGauss3rdbinarylibs=${WORKSPACE}/openGauss-third_party_binarylibs
gcc_version=10.3

if [[ "$gitcodeTargetBranch"x = "dev10"x || "$gitcodeTargetBranch"x = "glt"x || "$gitcodeTargetBranch"x = "iud_dev"x || "$gitcodeTargetBranch"x = "tp_poc"x || "$gitcodeTargetBranch"x = "datavec_poc"x ]]; then
    echo "skip $gitcodeTargetBranch branch gate"
    exit 0
fi

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
    
    if [[ "${gitcodePullRequestIid}" == "5986" || "${gitcodePullRequestIid}" == "5987" ]]; then
    	download_source_from_gitcode "https://gitcode.com/zhang_xubo/openGauss-OM.git" fixver OM
    else
    	download_source_from_gitcode ${om_repo} ${gitcodeTargetBranch} OM
    
    fi
}

function merge_source_code() {
    cd ${WORKSPACE}/openGauss
    git config --global user.email "570157209@qq.com"
    git config --global user.name "l1azzzy"
    git rev-parse --is-inside-work-tree
    git config remote.origin.url ${openGaussServer_Http_Repo_Url}
    git fetch origin refs/merge-requests/${gitcodePullRequestIid}/head:refs/merge-requests/${gitcodePullRequestIid}/head
    git merge --no-verify refs/merge-requests/${gitcodePullRequestIid}/head --no-edit
    #git fetch origin refs/merge-requests/${gitcodePullRequestIid}/merge:refs/merge-requests/${gitcodePullRequestIid}/merge
    #git merge --no-verify -m 'msg' refs/merge-requests/${gitcodePullRequestIid}/merge
    #git fetch --tags --force --progress origin ${gitcodeMergeRef}:${gitcodeMergeRef}
    #git checkout -b ${gitcodeMergeRef} ${gitcodeMergeRef}
   # git fetch origin refs/merge-requests/${gitcodePullRequestIid}/head:refs/merge-requests/${gitcodePullRequestIid}/head
  #  git merge --no-verify refs/merge-requests/${gitcodePullRequestIid}/head
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

function download_basepkg() {

    cd /data/om/
    if [ "$gitcodeTargetBranch" == "2.0.0" ]; then
            base_package_path=openGauss-2.0.0-openEuler-64bit-all.tar.gz
    elif [[ "$gitcodeTargetBranch"x = "master"x || "$gitcodeTargetBranch"x = "7.0.0"x ]]; then
            base_package_path=openGauss-All-6.0.0-openEuler20.03-x86_64.tar.gz
    elif [ "$gitcodeTargetBranch" == "7.0.0-RC2" ]; then
            base_package_path=openGauss-All-6.0.0-openEuler20.03-x86_64.tar.gz
    elif [ "$gitcodeTargetBranch" == "7.0.0-RC1" ]; then
            base_package_path=openGauss-All-6.0.0-openEuler20.03-x86_64.tar.gz
    else
            base_package_path=openGauss-3.0.0-openEuler-64bit-all.tar.gz
    fi

    wget ftp://192.168.0.9/3rd/ombase/${base_package_path}.tar.gz

}

function get_gcc_version() {
    if [[ "$gitcodeTargetBranch"x = "2.0.0"x || "$gitcodeTargetBranch"x = "3.0.0"x || "$gitcodeTargetBranch"x = "5.0.0"x ]]; then
        gcc_version=7.3
    fi
}

function export_env() {
	export CC=${openGauss3rdbinarylibs}/buildtools/gcc${gcc_version}/gcc/bin/gcc
    export cc=${openGauss3rdbinarylibs}/buildtools/gcc${gcc_version}/gcc/bin/gcc
    export LD_LIBRARY_PATH=${openGauss3rdbinarylibs}/buildtools/gcc${gcc_version}/gcc/lib64:$LD_LIBRARY_PATH
}

function pkg() {
    # 打包工程
    source /etc/profile
    cd ${WORKSPACE}/openGauss/build/script
    chmod +x build_opengauss.sh
    # 2.0.0和3.0.0用make编译，其他用cmake编译
    if [[ $gitcodeTargetBranch = "2.0.0" || $gitcodeTargetBranch = "3.0.0" ]]; then
        sed -i "s/make -sj 8/make -sj24/g" mpp_package.sh
        sed -i "s/make install -sj 8/make install -sj24/g" mpp_package.sh
    else
        sed -i "s/CMAKE_PKG=\"N\"/CMAKE_PKG=\"Y\"/" build_opengauss.sh
        sed -i "s/make -sj \${cpus_num}/make -sj24/g" utils/cmake_compile.sh
        sed -i "s/make install -sj \${cpus_num}/make install -sj24/g" utils/cmake_compile.sh
    fi

	sed -i '/exit 0/d' ${WORKSPACE}/openGauss/build.sh
    cd ${WORKSPACE}/openGauss
    sh build.sh -m release -3rd ${WORKSPACE}/openGauss-third_party_binarylibs -pkg
	if [[ $? -ne 0 ]]; then
        echo "ERROR: server pkg failed."
        exit 1
    fi

    cd ${WORKSPACE}/OM
    sh build.sh -3rd ${WORKSPACE}/openGauss-third_party_binarylibs
    if [[ $? -ne 0 ]]; then
        echo "ERROR: om pkg failed."
        exit 1
    fi
    # copy om包
    cp ${WORKSPACE}/OM/package/*.tar.gz ${WORKSPACE}/openGauss/output/.
}

function install_upgrade() {
    # 执行om ##
    pkg_branch="2.1.0"
    if [ "${gitcodeTargetBranch}"x == "master"x ]; then
        pkg_branch="8.0.0-RC1"
    elif [ "${gitcodeTargetBranch}"x == "7.0.0-RC2"x ]; then
        pkg_branch="7.0.0-RC2"
    elif [ "${gitcodeTargetBranch}"x == "7.0.0"x ]; then
        pkg_branch="7.0.0"
    elif [ "${gitcodeTargetBranch}"x == "6.0.0"x ]; then
        pkg_branch="6.0.6"
    elif [ "${gitcodeTargetBranch}"x == "datavec_poc"x ]; then
        pkg_branch="6.0.2"
    elif [ "${gitcodeTargetBranch}"x == "tp_poc"x ]; then
        pkg_branch="6.0.3"
    elif [ "${gitcodeTargetBranch}"x == "6.0.5"x ]; then
        pkg_branch="6.0.5"
    elif [ "${gitcodeTargetBranch}"x == "3.0.0"x ]; then
        pkg_branch="3.0.7"
    elif [ "${gitcodeTargetBranch}"x == "2.0.0"x ]; then
        pkg_branch="2.0.5"
    elif [ "${gitcodeTargetBranch}"x == "5.0.0"x ]; then
        pkg_branch="5.0.5"
    else
        pkg_branch=$gitcodeTargetBranch
    fi

    echo "pakcage version is: $pkg_branch"

    # om放置文件的路径
    cd /data/om
    # 安装
    #sh automated-test.sh ${WORKSPACE} ${pkg_branch}

    #升级(基础包未传入)
    sh auto_upgradectl.sh ${WORKSPACE} ${pkg_branch}
    if [[ $? -ne 0 ]]; then
        echo "ERROR: om upgrade failed."
        exit 1
    fi
	
    if [ -e /home/OM/ssh/known_hosts ]; then
        rm -rf ~/.ssh/*
        #cp /home/OM/ssh/* ~/.ssh/
    fi
}

function main() {
    download_source
    #merge_source_code
    download_binarylibs
    get_gcc_version
    export_env
    pkg
    download_basepkg
    install_upgrade
}

main "$@"
