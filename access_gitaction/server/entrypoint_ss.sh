#!/bin/bash

#echo "gitcodePullRequestIid: ${gitcodePullRequestIid}"
#echo "gitcodeAfterCommitSha: ${gitcodeAfterCommitSha}"
#echo "gitcodeRef: refs/merge-requests/${gitcodePullRequestIid}/merge"
#git config --global core.compression 0
#开发板版本为5.1.0
if [[ "$gitcodeTargetBranch"x = "dev_board"x ]]; then
    gitcodeTargetBranch="5.1.0"
fi
sync && echo 3>/proc/sys/vm/drop_caches
ipcrm -a

#本地测试
gitcodeTargetBranch=master
WORKSPACE=/usr1/gauss_jenkins/jenkins/workspace
openGaussServer_Http_Repo_Url=https://gitcode.com/opengauss/openGauss-server.git

openGauss3rdbinarylibs=${WORKSPACE}/openGauss-third_party_binarylibs
cbb_repo=https://gitcode.com/opengauss/CBB.git
dss_repo=https://gitcode.com/opengauss/DSS.git
dms_repo=https://gitcode.com/opengauss/DMS.git
gcc_version=10.3

#定义6.0.x系列分支的特殊依赖分支
CBB_BRANCH_FOR_600="6.0.6_DEV"
DSS_BRANCH_FOR_600="6.0.6_DEV"
DMS_BRANCH_FOR_600="6.0.6_DEV"

if [[ "$gitcodeTargetBranch"x = "2.0.0"x || "$gitcodeTargetBranch"x = "3.0.0"x || "$gitcodeTargetBranch"x = "dev"x  || "$gitcodeTargetBranch"x = "iud_dev"x || "$gitcodeTargetBranch"x = "tp_poc"x || "$gitcodeTargetBranch"x = "datavec_poc"x ]]; then
    echo "skip $gitcodeTargetBranch branch gate"
    exit 0
fi

if [[ ! -d $WORKSPACE ]]; then
    mkdir -p $WORKSPACE
fi

function prepare_deps() {
    mkdir -p ${WORKSPACE}/dependency/cmake

    if [ "$(uname -m)" = "aarch64" ]; then
        tar -xf /cmake-3.19.5-Linux-aarch64.tar.gz -C ${WORKSPACE}/dependency/cmake/ --strip-components 1
    else
        tar -xf /cmake-3.19.5-Linux-x86_64.tar.gz -C ${WORKSPACE}/dependency/cmake/ --strip-components 1
    fi

    export CMAKEHOME=/usr1/gauss_jenkins/jenkins/workspace/dependency/cmake
    export LD_LIBRARY_PATH=$CMAKEHOME/lib:$LD_LIBRARY_PATH
    export PATH=$CMAKEHOME/bin:$PATH

    echo "export CMAKEHOME=/usr1/gauss_jenkins/jenkins/workspace/dependency/cmake" >> /opt/envfile
    echo "export CMAKEHOME=export PATH=$CMAKEHOME/bin:$PATH" >> /opt/envfile
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

function get_dep_branch() {
    # 判断是否为6.0.x系列分支，使用特殊依赖分支
    if [[ "$gitcodeTargetBranch"x == "6.0.0"x ]] || [[ "$gitcodeTargetBranch"x =~ ^6.0.[0-9]+$ ]]; then
        echo "Detected 6.0.x branch: $gitcodeTargetBranch, using DEV branch for dependencies"
        cbb_branch=$CBB_BRANCH_FOR_600
        dss_branch=$DSS_BRANCH_FOR_600
        dms_branch=$DMS_BRANCH_FOR_600
    else
        cbb_branch=$gitcodeTargetBranch
        dss_branch=$gitcodeTargetBranch
        dms_branch=$gitcodeTargetBranch
    fi
}

function download_source() {
    cd ${WORKSPACE}
    # 获取依赖分支
    get_dep_branch

    download_source_from_gitcode ${openGaussServer_Http_Repo_Url} ${gitcodeTargetBranch} openGauss
    download_source_from_gitcode ${cbb_repo} ${cbb_branch} CBB
    download_source_from_gitcode ${dss_repo} ${dss_branch} DSS
    download_source_from_gitcode ${dms_repo} ${dms_branch} DMS
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

function get_ddes_commit_id() {
    # 通过=分割字符，获取=后面的commit id
    list=($(awk -F= '{print $2}' ${WORKSPACE}/openGauss/src/gausskernel/ddes/ddes_commit_id))
    dms_commit_id=${list[0]}
    dss_commit_id=${list[1]}
    cbb_commit_id=${list[2]}
    if [[ -z $dms_commit_id || -z $dss_commit_id ]]; then
        echo "ERROR: not fount ddes commit id"
        exit 1
    fi
}

function compile_deps() {
    echo "Start to build CBB.."
    cd ${WORKSPACE}/CBB
    git reset ${cbb_commit_id} --hard
    cd ${WORKSPACE}/CBB/build/linux/opengauss
    sh -x build.sh -m Debug -3rd ${openGauss3rdbinarylibs}

    if [[ $? -ne 0 ]]; then
        echo "ERROR: cbb compile failed."
        exit 1
    fi
}

function compile_ddes() {
    echo "Start to build DSS.."
    cd ${WORKSPACE}/DSS
    git reset ${dss_commit_id} --hard
    cd ${WORKSPACE}/DSS/build/linux/opengauss
    sh -x build.sh -3rd ${WORKSPACE}/openGauss-third_party_binarylibs -m DebugDsstest -t cmake
    #sh -x build.sh -3rd ${WORKSPACE}/openGauss-third_party_binarylibs -m Debug -t cmake
    if [[ $? -ne 0 ]]; then
        echo "ERROR: dss compile failed."
        exit 1
    fi

    echo "Start to build DMS.."
    cd ${WORKSPACE}/DMS
    git reset ${dms_commit_id} --hard
    cd ${WORKSPACE}/DMS/build/linux/opengauss
    sh -x build.sh -3rd ${openGauss3rdbinarylibs} -m DMSTest

    if [[ $? -ne 0 ]]; then
        echo "ERROR: dms compile failed."
        exit 1
    fi
}

function get_gcc_version() {
    if [[ "$gitcodeTargetBranch"x = "2.0.0"x || "$gitcodeTargetBranch"x = "3.0.0"x || "$gitcodeTargetBranch"x = "5.0.0"x ]]; then
        gcc_version=7.3
    fi
}

function export_env() {
    source /etc/profile
    #export CC=${openGauss3rdbinarylibs}/buildtools/gcc${gcc_version}/gcc/bin/gcc
    #export cc=${openGauss3rdbinarylibs}/buildtools/gcc${gcc_version}/gcc/bin/gcc
    #export LD_LIBRARY_PATH=${openGauss3rdbinarylibs}/buildtools/gcc${gcc_version}/gcc/lib64:$LD_LIBRARY_PATH
    export GCC_PATH=${openGauss3rdbinarylibs}/buildtools/gcc${gcc_version}/
    export CC=$GCC_PATH/gcc/bin/gcc
    #export cc=$GCC_PATH/gcc/bin/gcc
    export CXX=$GCC_PATH/gcc/bin/g++
    export LD_LIBRARY_PATH=${GCC_PATH}/gcc/lib64:${GCC_PATH}/isl/lib:${GCC_PATH}/mpc/lib/:${GCC_PATH}/mpfr/lib/:${GCC_PATH}/gmp/lib/:$LD_LIBRARY_PATH
    export LD_LIBRARY_PATH=${binarylibs_path}/kernel/dependency/zstd/lib:$LD_LIBRARY_PATH
    export PATH=${GCC_PATH}/gcc/bin:$PATH
}

function compile_cmake() {
    chmod -R 755 /data/
    echo "Start to build opengauss================================================"
    cd ${WORKSPACE}/openGauss/build/script/
    chmod +x build_opengauss.sh

    # cmake编译
    sed -i 's/declare CMAKE_PKG="N"/declare CMAKE_PKG="Y"/g' build_opengauss.sh
    sed -i "s/make -sj \${cpus_num}/make -sj16/g" utils/cmake_compile.sh
    sed -i "s/make install -sj \${cpus_num}/make install -sj16/g" utils/cmake_compile.sh
    sed -i '/exit 0/d' ${WORKSPACE}/openGauss/build.sh
    sh build_opengauss.sh -m debug -3rd ${WORKSPACE}/openGauss-third_party_binarylibs
    if [ $? -ne 0 ]; then
        echo "ERROR: cmake openGauss compile failed."
        cat ${WORKSPACE}/openGauss/build/script/makemppdb_pkg.log
        exit 1
    fi
    echo "end to build opengauss================================================"
}

function complie() {
    compile_deps
    compile_ddes
    compile_cmake
}

function clean() {
    ps -ef |grep test | awk '{ print $2 }' | xargs kill -9
}

function cat_log() {
    if [[ ! -d ${WORKSPACE}/openGauss/tmp_build/log ]]; then
        echo "ERROR: No log file generated"
        exit 1
    fi
    cd ${WORKSPACE}/openGauss/tmp_build/log/
    log_files=$(ls ${WORKSPACE}/openGauss/tmp_build/log)
    for file in $log_files; do
        cat $file
    done
}

function make_fastcheck_ss() {
    chmod -R 755 /usr1/
    chmod -R 755 /data/
    chown -R test:test /usr1/
    su - test -c "source /data/ss/ss_env.ini && export && cd ${WORKSPACE}/openGauss/tmp_build/ && make fastcheck_ss p=8798 -sj"
    if [[ $? == 0 ]]; then
        echo "fastcheck_ss success."
    else
        echo "ERROR: fastcheck_ss failed."
        cat_log
        exit 1
    fi
}

function main() {
    #clean
    download_source
   # merge_source_code
    download_binarylibs
    get_ddes_commit_id
    get_gcc_version
    export_env
    prepare_deps
    complie
    make_fastcheck_ss
}

main "$@"