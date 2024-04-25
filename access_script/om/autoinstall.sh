#!/bin/bash
echo "giteePullRequestIid: ${giteePullRequestIid}"
echo "giteeAfterCommitSha: ${giteeAfterCommitSha}"
echo "giteeRef: ${giteeRef}"
export https_proxy=xxxx
git config --global core.compression 0

sync && echo 3>/proc/sys/vm/drop_caches

# 本地测试
user=test_ss
cm_port=48218
db_port=49219

openGaussServer_Http_Repo_Url=https://gitee.com/opengauss/openGauss-server.git
cbb_repo=https://gitee.com/opengauss/CBB.git
dss_repo=https://gitee.com/opengauss/DSS.git
dms_repo=https://gitee.com/opengauss/DMS.git

gcc_version=10.3

echo ${NODE_NAME}
# path 
install_path=${WORKSPACE}/install
xml_file=${WORKSPACE}/1p1s.xml
env_path=${WORKSPACE}/ENVFILE
DSS_HOME=${install_path}/dss_home
BENCHMARKSQL_PATH=/usr1/test_ss/benchmarksql/run
openGauss3rdbinarylibs=${WORKSPACE}/openGauss-third_party_binarylibs

if [[ "$giteeTargetBranch"x = "2.0.0"x || "$giteeTargetBranch"x = "3.0.0"x || "$giteeTargetBranch"x = "dev"x ]]; then
    echo "skip $giteeTargetBranch branch gate"
    exit 0
fi
#配置信息，根据需要修改
if [ "$NODE_NAME" = "node135" ]; then
	#share disk
    DATA_LUN=/dev/disk/by-id/wwn-0x6382028100ed96ac5a24553700000062
    XLOG_LUN=/dev/disk/by-id/wwn-0x6382028100ed96ac5a24553700000063
    CM_LUN1=/dev/disk/by-id/wwn-0x6382028100ed96ac5a24553700000064
    CM_LUN2=/dev/disk/by-id/wwn-0x6382028100ed96ac5a24553700000065
    # 定义hostname和IP地址的数组
    hostnames=("openGauss135" "openGauss137")
    ips=("20.20.20.135" "20.20.20.137")
elif [ "$NODE_NAME" = "node79" ]; then
    DATA_LUN=/dev/disk/by-id/wwn-0x6382028100c0772b315389ae0000004c
    XLOG_LUN=/dev/disk/by-id/wwn-0x6382028100c0772b315389ae00000052
    CM_LUN1=/dev/disk/by-id/wwn-0x6382028100c0772b315389ae00000055
    CM_LUN2=/dev/disk/by-id/wwn-0x6382028100c0772b315389ae00000056
    hostnames=("openGauss79" "openGauss82")
    ips=("20.20.20.79" "20.20.20.82")
else
    echo "执行节点未配置"
    exit 1
fi

function create_xml
{
    # 将hostname数组转换为逗号分隔的字符串，用于nodeNames参数
    IFS=','; nodeNames="${hostnames[*]}"; IFS=$' \t\n'
    # 同样，将IP地址数组转换为逗号分隔的字符串，用于cmServerListenIp1参数和backIp1s参数
    IFS=','; cmServerListenIp1="${ips[*]}"; IFS=$' \t\n'
    IFS=','; backIp1s="${ips[*]}"; IFS=$' \t\n'

    # 动态构建<DEVICE>部分
    device_section=""
    for i in "${!hostnames[@]}"; do
        if [ $i -eq 0 ]; then
            # 第一个DEVICE包含完整的cm相关参数
            device_section+="
            <DEVICE sn=\"${hostnames[$i]}\">
                <PARAM name=\"name\" value=\"${hostnames[$i]}\"/>
                <PARAM name=\"azName\" value=\"AZ1\"/>
                <PARAM name=\"azPriority\" value=\"1\"/>
                <PARAM name=\"backIp1\" value=\"${ips[$i]}\"/>
                <PARAM name=\"sshIp1\" value=\"${ips[$i]}\"/>
                <PARAM name=\"cmDir\" value=\"${install_path}/cm\"/>
                <PARAM name=\"cmsNum\" value=\"1\"/>
                <PARAM name=\"cmServerPortBase\" value=\"${cm_port}\"/>
                <PARAM name=\"cmServerListenIp1\" value=\"$cmServerListenIp1\"/>
                <PARAM name=\"cmServerlevel\" value=\"1\"/>
                <PARAM name=\"cmServerRelation\" value=\"$nodeNames\"/>
                <PARAM name=\"dataNum\" value=\"1\"/>
                <PARAM name=\"dataPortBase\" value=\"${db_port}\"/>
                <PARAM name=\"dataNode1\" value=\"${install_path}/data/dn,${hostnames[$((1-$i))]},${install_path}/data/dn\"/>
            </DEVICE>"
        else
            # 其他DEVICE按照提供的格式，仅包含cmDir
            device_section+="
            <DEVICE sn=\"${hostnames[$i]}\">
                <PARAM name=\"name\" value=\"${hostnames[$i]}\"/>
                <PARAM name=\"azName\" value=\"AZ1\"/>
                <PARAM name=\"azPriority\" value=\"1\"/>
                <PARAM name=\"backIp1\" value=\"${ips[$i]}\"/>
                <PARAM name=\"sshIp1\" value=\"${ips[$i]}\"/>
                <PARAM name=\"cmDir\" value=\"${install_path}/cm\"/>
            </DEVICE>"
        fi
    done

# 构建完整的XML内容
xml_content=$(cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<ROOT>
    <CLUSTER>
        <PARAM name="clusterName" value="cluster" />
        <PARAM name="nodeNames" value="$nodeNames" />
        <PARAM name="gaussdbAppPath" value="${install_path}/app" />
        <PARAM name="gaussdbLogPath" value="${install_path}/log" />
        <PARAM name="tmpMppdbPath" value="${install_path}/tmp"/>
        <PARAM name="gaussdbToolPath" value="${install_path}/tool" />
        <PARAM name="corePath" value="/home/core"/>
        <PARAM name="backIp1s" value="$backIp1s" />
        <PARAM name="enable_dss" value="on"/>
        <PARAM name="dss_home" value="${install_path}/dss_home"/>
        <PARAM name="dss_vg_info" value="data:${DATA_LUN},log:${XLOG_LUN}"/>
        <PARAM name="votingDiskPath" value="${CM_LUN1}"/>
        <PARAM name="shareDiskDir" value="${CM_LUN2}"/>
        <PARAM name="ss_dss_vg_name" value="data"/>
        <PARAM name="dss_ssl_enable" value="off"/>
    </CLUSTER>
    <DEVICELIST>$device_section
    </DEVICELIST>
</ROOT>
EOF
)
	echo "$xml_content"
}

if [[ -d WORKSPACE ]]; then
    mkdir -p $WORKSPACE
fi

function auto_(){
    expect <<-EOF
        spawn $*
        set timeout -1
        expect {
            "yes/no" { send "yes\n"; exp_continue }
            "denied" { exit 1; }
            "*assword:" { send "Huawei@123\n"; exp_continue }
            "anger*\n*yes*" { send "yes\n"; exp_continue }
            "Pdb" { interact }
            "pass phrase for*:" { send "Huawei@123\n"; exp_continue  }
            "passphrase" { send "Huawei@123\n"; exp_continue  }
            "database:" { send "Huawei@123\n"; exp_continue  }
        }
        #expect eof
EOF
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

function check_ddescommitid_change() {
    # 指定 ddescommitid 文件的路径
    cd ${WORKSPACE}/openGauss/
    ddescommitid_file_path="${WORKSPACE}/openGauss/src/gausskernel/ddes/ddes_commit_id"

    # 获取仓库的最新 commit id
    latest_commit_id=$(git log -n 1 --skip 1 --format=format:"%H")

    # 获取文件的最新 commit id
    file_commit_id=$(git log -n 1 --format=format:"%H" -- $ddescommitid_file_path)

    # 比较两个 commit id，如果它们相同，那么最新的提交修改了该文件
    if [ "$latest_commit_id" == "$file_commit_id" ]; then
        echo "ddes commit id file has been modified in the latest commit."
        return 1
    else
        echo "ddes commit id file has not been modified in the latest commit."
        return 0
    fi
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
    elif [[ "$os_name"x = "openEuler"x ]] && [[ "$cpu_arc"x = "aarch64"x ]]; then
        binarylibs_file=$BINARYLIBS_NAME_OPENEULER_ARM
    elif [[ "$os_name"x = "openEuler"x ]] && [[ "$cpu_arc"x = "x86_64"x ]]; then
        binarylibs_file=$BINARYLIBS_NAME_OPENEULER_X86
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
    if [[ "$giteeTargetBranch"x = "5.0.0"x ]]; then
        wget https://opengauss.obs.cn-south-1.myhuaweicloud.com/5.0.0/binarylibs/gcc7.3/${binarylibs_file}.tar.gz -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz -q
    elif [[ "$giteeTargetBranch"x = "5.1.0"x ]]; then
        wget https://opengauss.obs.cn-south-1.myhuaweicloud.com/5.1.0/binarylibs/gcc10.3/${binarylibs_file}.tar.gz -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz -q
    elif [[ "$giteeTargetBranch"x = "master"x || "$giteeTargetBranch"x = "dev"x ]]; then
        wget https://opengauss.obs.cn-south-1.myhuaweicloud.com/latest/binarylibs/gcc10.3/${binarylibs_file}.tar.gz -O ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz -q
    else
        echo "ERROR: $giteeTargetBranch branch not found"
    fi
    set +e

    cd ${WORKSPACE}
    mkdir -p ${WORKSPACE}/openGauss-third_party_binarylibs
    tar -zxf ${WORKSPACE}/openGauss-third_party_binarylibs.tar.gz -C openGauss-third_party_binarylibs --strip-components 1
}

function compile_cbb() {
    echo "Start to build CBB.."
    cd ${WORKSPACE}/CBB/
    git reset --hard ${cbb_commit_id}
    cd ${WORKSPACE}/CBB/build/linux/opengauss
    
    sh -x build.sh -3rd ${openGauss3rdbinarylibs}

    if [[ $? -ne 0 ]]; then
        echo "ERROR: cbb compile failed."
        exit 1
    fi
}

function compile_ddes() {
    echo "Start to build DSS.."
    cd ${WORKSPACE}/DSS
    git reset --hard ${dss_commit_id}
    cd ${WORKSPACE}/DSS/build/linux/opengauss
    sh -x build.sh -3rd ${WORKSPACE}/openGauss-third_party_binarylibs -t cmake

    if [[ $? -ne 0 ]]; then
        echo "ERROR: dss compile failed."
        exit 1
    fi

    echo "Start to build DMS.."
    cd ${WORKSPACE}/DMS
    git reset --hard ${dms_commit_id}
    cd ${WORKSPACE}/DMS/build/linux/opengauss
    sh -x build.sh -3rd ${openGauss3rdbinarylibs}

    if [[ $? -ne 0 ]]; then
        echo "ERROR: dms compile failed."
        exit 1
    fi
}

function export_env() {
	source /etc/profile
    export CC=${openGauss3rdbinarylibs}/buildtools/gcc${gcc_version}/gcc/bin/gcc
    export cc=${openGauss3rdbinarylibs}/buildtools/gcc${gcc_version}/gcc/bin/gcc
    export GCCFOLDER=${openGauss3rdbinarylibs}/buildtools/gcc${gcc_version}
    export LD_LIBRARY_PATH=${openGauss3rdbinarylibs}/buildtools/gcc${gcc_version}/gcc/lib64:$LD_LIBRARY_PATH
    export LD_LIBRARY_PATH=$GCCFOLDER/gcc/lib64:$GCCFOLDER/isl/lib:$GCCFOLDER/mpc/lib/:$GCCFOLDER/mpfr/lib/:$GCCFOLDER/gmp/lib/:$LD_LIBRARY_PATH
}

function compile_server() {
    echo "Start to build opengauss================================================"
    cd ${WORKSPACE}/openGauss/
    cpus_num=$(grep -w processor /proc/cpuinfo|wc -l)
    sed -i "s/make -sj 20/make -sj ${cpus_num}/g" ${WORKSPACE}/openGauss/build/script/utils/make_compile.sh
    sed -i "s/make install -sj 8/make install -sj ${cpus_num}/g" ${WORKSPACE}/openGauss/build/script/utils/make_compile.sh

    sh build.sh -3rd ${WORKSPACE}/openGauss-third_party_binarylibs -pkg
    if [ $? -ne 0 ]; then
        echo "ERROR: cmake openGauss compile failed."
        cat ${WORKSPACE}/openGauss/build/script/makemppdb_pkg.log
        exit 1
    fi
    echo "end to build opengauss================================================"
}

function get_ddes_commit_id() {
    # 通过=分割字符，获取=后面的commit id
    list=($(awk -F= '{print $2}' ${WORKSPACE}/openGauss/src/gausskernel/ddes/ddes_commit_id))
    dms_commit_id=${list[0]}
    dss_commit_id=${list[1]}
    cbb_commit_id=${list[2]}
	echo ${dms_commit_id}
    echo ${dss_commit_id}
    echo ${cbb_commit_id}
    if [[ -z $dms_commit_id || -z $dss_commit_id ]]; then
        echo "ERROR: not fount ddes commit id"
        exit 1
    fi
}

function complie() {
    get_ddes_commit_id
    compile_cbb
    compile_ddes
    compile_server
}

function clean_function() {
    ps -ef | grep test_ss | awk '{ print $2 }' | xargs kill -9
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

all_node_ssh_proc()
{
    for ip in "${ips[@]}"
    do
      echo "Executing on $ip"
      auto_ ssh root@$ip $*
    done
}

pre_un_install()
{
	echo "==============clean env==================="
    su - ${user}<<EOF
        source ${env_path}
        gs_uninstall --delete-data
EOF
}

function clean_env()
{
	all_node_ssh_proc "pkill -9 -u ${user}"
    all_node_ssh_proc rm -rf ${install_path}
    all_node_ssh_proc rm -rf ${env_path}
    all_node_ssh_proc rm -rf ${xml_file}
    all_node_ssh_proc "su - ${user} -c 'ipcrm -a'" >/dev/null
}

get_tar()
{
    #最新包
    if [[ ! -d ${install_path}/gauss_pack ]]; then
        mkdir -p ${install_path}/gauss_pack
    fi
    cd ${install_path}

    wget https://opengauss.obs.cn-south-1.myhuaweicloud.com/latest/arm/openGauss-6.0.0-RC1-openEuler-64bit-all.tar.gz

    #解压包
    cd ${install_path}/gauss_pack
    rm -rf *
    tar -zxf ../openGauss*.tar.gz

    echo "==========change tar========== "
    #替换包
    \cp ${WORKSPACE}/openGauss/output/*  ${install_path}/gauss_pack

    tar -zxf openGauss*om.tar.gz
    chmod 777 -R ${install_path}/

}

# #预安装
pre_install()
{
	echo "$xml_content" > ${xml_file}
	set -e
    echo "==============pre_install==================="
    chmod 777 -R ${install_path}/
    chmod 777 -R ${xml_file}
    cd ${install_path}/gauss_pack/script/
    auto_ ./gs_preinstall -U ${user} -G ${user}  --sep-env-file=${env_path} -X ${xml_file}
    chmod 777 -R ${xml_file}
    all_node_ssh_proc chmod 777 -R ${install_path}/
    all_node_ssh_proc chmod 777 -R ${WORKSPACE}
}

#安装
om_install()
{
	set -e
    echo "==============install==================="
    all_node_ssh_proc chmod 777 -R ${install_path}
su - ${user}<<EOF
    function auto_(){
        expect <<-EOD
            spawn \$*
            set timeout -1
            expect {
                "yes/no" { send "yes\n"; exp_continue }
                "denied" { exit 1; }
                "*assword:" { send "openGauss1#2_3\\\$00\n"; exp_continue }
                "anger*\n*yes*" { send "yes\n"; exp_continue }
                "Pdb" { interact }
                "pass phrase for*:" { send "openGauss1#2_3\\\$00\n"; exp_continue  }
                "passphrase" { send "openGauss1#2_3\\\$00\n"; exp_continue  }
                "database:" { send "Huawei@123\n"; exp_continue  }
            }
EOD
    }
    source ${env_path}
    auto_ gs_install -X ${xml_file}
    #查看集群状态
    cm_ctl query -Cvdip
EOF
}

set_guc()
{
    all_node_ssh_proc sed -i 's/_LOG_LEVEL=7/_LOG_LEVEL=255/g' ${DSS_HOME}/cfg/dss_inst.ini
    su - ${user}<<EOF
        source ${env_path}
        #查看集群状态
        gs_guc set -N all -I all -h "host all all 20.20.20.135/32 sha256"
        gs_guc set -N all -I all -c 'ss_log_level = 255'
        cm_ctl stop && cm_ctl start
        cm_ctl switchover -a
        cm_ctl query -Cvdip
EOF
}

create_user()
{
    su - ${user}<<EOF
        source  ${env_path}
        #创建用户
        echo " =================  create tpcc user    ================="
        dsscmd -v
        gsql -d postgres -p ${db_port} -r -c "create database tpcc;create user tpcc_user with password 'Huawei@123';grant all privileges to tpcc_user;"
        cm_ctl query -Cvipd; cm_ctl stop; cm_ctl start
EOF
}

kill_dn() 
{
    echo " =================kill primary================="
    su - ${user} -c "
        for i in {1..6};
        do
            ps ux | grep -v grep | grep 'bin/gaussdb' | awk '{print \$2}'
            ps ux | grep -v grep | grep 'bin/gaussdb' | awk '{print \$2}' | xargs kill -9
            sleep 6;
        done
    "
}

tpcc_build()
{   
	set -e
    echo " =================   tpcc building    ================="
    cd $BENCHMARKSQL_PATH
    sh runDatabaseBuild.sh props_135.pg >/dev/null || exit 1
    echo " =================   tpcc build finished   ================="
}

tpcc_run()
{    
	set -e
    echo " =================   tpcc running    ================="
    cd $BENCHMARKSQL_PATH
    sh runBenchmark.sh props_$1.pg > temp.log || exit 1
    tail -n 7 temp.log
    tail -n 7 temp.log >> install_tpcc.log
    rm temp.log
    echo " =================   tpcc run finished    ================="
}

test_tpcc()
{
	set -e
    echo "==============test tpcc==================="
    tpcc_build
    tpcc_run 135
    #su - ${user} -c "source ${env_path}; cm_ctl query -Cvipd"
    kill_dn
    sleep 120
    su - ${user} -c "source ${env_path}; cm_ctl query -Cvipd" || exit 1
    tpcc_run 137
    echo "==============start cluster && switchover==================="
    su - ${user} -c "source ${env_path}; cm_ctl start; cm_ctl query -Cvipd; cm_ctl switchover -a; cm_ctl query -Cvdip" || exit 1
    tpcc_run 135
    su - ${user} -c "source ${env_path}; cm_ctl query -Cvipd" || exit 1
}

function main() {
    download_source
    merge_source_code
    check_ddescommitid_change
    download_binarylibs
    export_env
    complie
    re_un_install
    clean_env
    get_tar
    create_xml
    pre_install
    om_install
    set_guc
    create_user
    test_tpcc
}

main "$@"

