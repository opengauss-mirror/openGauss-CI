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

openGauss3rdbinarylibs=${WORKSPACE}/openGauss-third_party_binarylibs
cbb_repo=https://gitee.com/opengauss/CBB.git
dss_repo=https://gitee.com/opengauss/DSS.git
dms_repo=https://gitee.com/opengauss/DMS.git
tmp_log=${WORKSPACE}/openGauss/tmp_build/log/

if [[ "$giteeTargetBranch"x != "master"x ]] && [[ "$giteeTargetBranch"x != "5.0.0"x ]]; then
    echo "only master and 5.0.0 branch pass"
    exit 0
fi

if [[ -d WORKSPACE ]]; then
    mkdir -p $WORKSPACE
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
    download_source_from_gitee ${cbb_repo} ${giteeTargetBranch} CBB
    download_source_from_gitee ${dss_repo} ${giteeTargetBranch} DSS
    download_source_from_gitee ${dms_repo} ${giteeTargetBranch} DMS
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

function compile_ddes() {
    # 通过=分割字符，获取=后面的commit id
    list=$($(awk -F= '{print $2}' ${WORKSPACE}/openGauss/src/gausskernel/ddes/ddes_commit_id))
    dms_commit_id=${list[0]}
    dss_commit_id=${list[1]}

    echo "Start to build DSS.."
    cd ${WORKSPACE}/DSS
    git checkout ${dss_commit_id}
    cd ${WORKSPACE}/DSS/build/linux/opengauss
    sh -x build.sh -3rd ${WORKSPACE}/openGauss-third_party_binarylibs -m ReleaseDsstest -t cmake

    echo "Start to build DMS.."
    cd ${WORKSPACE}/DMS
    git checkout ${dms_commit_id}
    cd ${WORKSPACE}/DMS/build/linux/opengauss
    sh -x build.sh -3rd ${openGauss3rdbinarylibs}
}

function compile_deps() {
    echo "Start to build CBB.."
    cd ${WORKSPACE}/CBB/build/linux/opengauss
    sh -x build.sh -3rd ${openGauss3rdbinarylibs}
}

function compile_cmake() {
    export PREFIX_HOME=${WORKSPACE}/mppdb_temp_install
    export GAUSSHOME=$PREFIX_HOME
    export LD_LIBRARY_PATH=$GAUSSHOME/lib:$LD_LIBRARY_PATH
    export PATH=$GAUSSHOME/bin:$PATH

    echo "Start to build opengauss================================================"
    cd ${WORKSPACE}/openGauss/build/script/
    chmod +x build_opengauss.sh
    # 修改为cmake编译方式
    sed -i 's/declare CMAKE_PKG="N"/declare CMAKE_PKG="Y"/g' build_opengauss.sh
    sed -i "s/make -sj \${cpus_num}/make -sj16/g" utils/cmake_compile.sh
    sed -i "s/make install -sj \${cpus_num}/make install -sj16/g" utils/cmake_compile.sh
    sh -x build_opengauss.sh -m debug -3rd ${WORKSPACE}/openGauss-third_party_binarylibs >cmake_result.log

    cat cmake_result.log | grep "all build has finished"

    if [ $? -ne 0 ]; then
        echo "ERROR: cmake openGauss compile failed."
        exit 1
    fi
    echo "end to build opengauss================================================"
}

function complie() {
    export PATH=/opt/install/cmake-3.26.3-linux-x86_64/bin:$PATH

    compile_deps
    compile_ddes
    compile_cmake
}

function move_log() {
    local source_path
    local target_path
    local source_file_name
    local target_file_name
    local datetime

    source_path=$1
    target_path=$2/$(date +%Y%m%d)
    echo "target path is $target_path"
    if [ ! -d "$target_path" ]; then
        mkdir -p "${target_path}"
    fi
    source_file_name=$(ls "$source_path")
    datetime=$(date +%Y%m%d%H%M%S)
    echo "today is ${datetime}"
    for data in $source_file_name; do
        # basename 去掉文件后缀
        target_file_name=$(basename "$data" .log)_"$datetime".log
        echo "$target_file_name"
        echo "start copy log"
        cp -rf "$source_path"/"$data" "$target_path"/"$target_file_name"
    done
}

function print_log() {
    local logs_path
    local logs_name

    logs_path=$1
    logs_name=$(ls "$logs_path")
    cd "$logs_path"
    for log in $logs_name; do
        # print log to screen
        cat "$log"
    done
}

function clean() {
    pkill -utest
}

function make_fastcheck_ss() {
    #chmod 777 -R ${WORKSPACE}
    chown -R test:test /usr1
    su - test -c "export PREFIX_HOME=${WORKSPACE}/openGauss/mppdb_temp_install &&
    export GAUSSHOME=$PREFIX_HOME &&
    export LD_LIBRARY_PATH=$GAUSSHOME/lib:$LD_LIBRARY_PATH &&
    export PATH=$GAUSSHOME/bin:$PATH && cd ${WORKSPACE}/openGauss/tmp_build/ && make fastcheck_ss p=8798 -sj"
    if [[ $? == 0 ]]; then
        echo "fastcheck_ss success."
    else
        echo "ERROR: fastcheck_ss failed."
        #print_log $tmp_log
        cat "$tmp_log"/initdb.log
        node1_log_count=$(ls ${WORKSPACE}/openGauss/src/test/regress/tmp_check/datanode1/pg_log/postgre*.log | wc -l)
        node2_log_count=$(ls ${WORKSPACE}/openGauss/src/test/regress/tmp_check/datanode2/pg_log/postgre*.log | wc -l)
        if [ $node1_log_count != 0 ]; then
            cat ${WORKSPACE}/openGauss/src/test/regress/tmp_check/datanode1/pg_log/postgre*.log
        fi
        if [ $node2_log_count != 0 ]; then
            cat ${WORKSPACE}/openGauss/src/test/regress/tmp_check/datanode2/pg_log/postgre*.log
        fi
        exit 1
    fi
}

function main() {
    clean
    download_source
    merge_source_code
    download_binarylibs
    complie
    make_fastcheck_ss
    echo "make fastcheck ss success !!!"
}

main "$@"
