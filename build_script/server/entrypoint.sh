#!/bin/bash

yum install -y bzip2 bzip2-devel curl libaio libaio-devel flex bison ncurses-devel glibc-devel patch dkms readline-devel \
which git libtool-ltdl-devel autoconf libtool python3 python3-devel python openssl-devel gcc-c++ make hostname iproute dos2unix

yum install libzstd -y

# build type
export WORKSPACE=/usr1/build/workspace
#export PKG_TYPE=release   ##release/debug/memcheck
export PKG_PRE_FIX=openGauss
export PKG_VERSION=5.1.0
export TARGET_OS=openEuler
export OUT_PUT_PATH=/usr1/build/workspace/result/
export VOLUME_PATH=/usr1/build/workspace/volume
export LOG_PATH=/usr1/build/workspace/log

#docker run传递参数
repo_branch=$1

export gcc_version=gcc10.3
if [ $repo_branch = "5.0.0" ]; then
    export PKG_VERSION=5.0.1
    export gcc_version=gcc7.3
fi

# source and branch
server_repo=https://gitee.com/opengauss/openGauss-server.git
server_branch=master
om_repo=https://gitee.com/opengauss/openGauss-OM.git
om_branch=master
jdbc_repo=https://gitee.com/opengauss/openGauss-connector-jdbc.git
jdbc_branch=master
odbc_repo=https://gitee.com/opengauss/openGauss-connector-odbc.git
odbc_branch=master
python_repo=https://gitee.com/opengauss/openGauss-connector-python-psycopg2.git
python_branch=master
cm_repo=https://gitee.com/opengauss/CM.git
cm_branch=master
dcf_repo=https://gitee.com/opengauss/DCF.git
dcf_branch=master
cbb_repo=https://gitee.com/opengauss/CBB.git
cbb_branch=master
dcc_repo=https://gitee.com/opengauss/DCC.git
dcc_branch=master
plugin_repo=https://gitee.com/opengauss/Plugin.git
plugin_branch=master

dss_repo=https://gitee.com/opengauss/DSS.git
dss_branch=master
dms_repo=https://gitee.com/opengauss/DMS.git
dms_branch=master

cm_restapi_repo=https://gitee.com/opengauss/CM-RestAPI.git
cm_restapi_branch=master

opengauss_source=${WORKSPACE}/openGauss

function download_from_gitee() {
    repo=$1
    branch=$2
    target_dir=$3
    echo "download source [${repo}], branch [${branch}]"

    git config --global core.compression 0
    a=0
    flag=0
    while [ $a -lt 3 ]
    do
    echo $a
    rm -rf ${WORKSPACE}/OM
    timeout 120 git clone ${repo} -b ${branch} ${target_dir} > /dev/null
    if [[ $? == 0 ]] ; then
        flag=1
        break
    fi
    a=`expr $a + 1`
    done

    if [[ $flag == 0 ]] ; then
        echo "clone code failed!"
        exit 1
    fi
}

function download_source() {
    cd ${opengauss_source}
    download_from_gitee ${server_repo} ${repo_branch} server
    download_from_gitee ${om_repo} ${repo_branch} OM
    download_from_gitee ${jdbc_repo} ${repo_branch} jdbc
    download_from_gitee ${odbc_repo} ${repo_branch} odbc
    download_from_gitee ${python_repo} ${repo_branch} python_driver2
    download_from_gitee ${cm_repo} ${repo_branch} CM
    download_from_gitee ${dcf_repo} ${repo_branch} DCF
    download_from_gitee ${cbb_repo} ${repo_branch} CBB
    download_from_gitee ${dcc_repo} ${repo_branch} DCC
    download_from_gitee ${server_repo} ${repo_branch} server_lite
    download_from_gitee ${plugin_repo} ${repo_branch} plugins
    download_from_gitee ${cm_restapi_repo} ${repo_branch} cm_restapi
    download_from_gitee ${dss_repo} ${repo_branch} DSS
    download_from_gitee ${dms_repo} ${repo_branch} DMS
}

function prepare_plugins() {
    echo "prepare plugins"
    cp -r ${opengauss_source}/plugins/contrib/dolphin ${opengauss_source}/server/contrib/
    cp -r ${opengauss_source}/plugins/contrib/assessment ${opengauss_source}/server/contrib/
    cd ${opengauss_source}/server/contrib/dolphin
    make write_git_commit git_repo_path=${opengauss_source}/plugins -k
    mv ${opengauss_source}/plugins/contrib/dolphin ${opengauss_source}/server_lite/contrib/
    cd ${opengauss_source}/server_lite/contrib/dolphin
    make write_git_commit git_repo_path=${opengauss_source}/plugins -k

}

function prepare_tools() {

    # prepare 3rd
    cd ${WORKSPACE};
    
    mkdir openGauss-third_party_binarylibs
    tar -zxf openGauss-third_party_binarylibs.tar.gz -C openGauss-third_party_binarylibs --strip-components 1

    os_plat=""
    if [ "$(uname -p)" == "x86_64" ]; then
        os_plat=openeuler_x86_64
    else
        os_plat=openeuler_aarch64
    fi

    # import gcc env
    export os_platform=${os_plat}
    export GCC_PATH=${WORKSPACE}/openGauss-third_party_binarylibs/buildtools/$gcc_version/
    export CC=$GCC_PATH/gcc/bin/gcc
    export CXX=$GCC_PATH/gcc/bin/g++
    export LD_LIBRARY_PATH=$GCC_PATH/gcc/lib64:$GCC_PATH/isl/lib:$GCC_PATH/mpc/lib/:$GCC_PATH/mpfr/lib/:$GCC_PATH/gmp/lib/:$LD_LIBRARY_PATH
    export PATH=$GCC_PATH/gcc/bin:$PATH

    # we need cmake version >= 3.16
    # cmake
    cd ${WORKSPACE}/dependency
    mkdir cmake
    tar -xf cmake-3.19.5-Linux.tar.gz -C cmake --strip-components 1
    export CMAKEHOME=${WORKSPACE}/dependency/cmake
    export LD_LIBRARY_PATH=$CMAKEHOME/lib:$LD_LIBRARY_PATH
    export PATH=${CMAKEHOME}/bin:${PATH}
        
}

echo "build opengauss entry"

start_time=$(date +'%F %H:%M:%S')

download_source

prepare_plugins

prepare_tools

echo "start to build opengass and package..."
echo "sh -x package_ci_master.sh -d ${WORKSPACE} -t ${PKG_TYPE} -v ${PKG_VERSION} -b build -o ${OUT_PUT_PATH} -l ${WORKSPACE}/openGauss-third_party_binarylibs"
sh package_ci_master.sh -d ${WORKSPACE} -t ${PKG_TYPE} -v ${PKG_VERSION} -b build -o ${OUT_PUT_PATH} -l ${WORKSPACE}/openGauss-third_party_binarylibs
if [ $? -ne 0 ]; then
    exit 1
fi

mv ${OUT_PUT_PATH}/* ${VOLUME_PATH}/

sh build_lite.sh
if [ $? -ne 0 ]; then
    exit 1
fi
mv ${opengauss_source}/server_lite/output/* ${VOLUME_PATH}/

end_time=$(date +'%F %H:%M:%S')
echo "build opengauss end..."
echo "build opengauss start time $start_time ."
echo "build opengauss end time $end_time ."
