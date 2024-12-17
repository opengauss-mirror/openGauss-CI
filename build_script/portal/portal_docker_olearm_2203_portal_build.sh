#!/bin/bash
# 本地测试
set -x

workspace=/data2/autobuild/portal
rm -rf ${workspace}
mkdir -p ${workspace}

env_work=/soft
giteeTargetBranch=master
portal_version=7.0.0rc1
package_arch=$(uname -p)

os_name=$(
    source /etc/os-release
    echo ${ID}22.03
)

portal_repo=https://gitee.com/opengauss/openGauss-migration-portal.git
obs_upload_path=obs://opengauss/latest/tools/${os_name}
portal_package_name=PortalControl-${portal_version}-${package_arch}.tar.gz
#chameleon=https://opengauss.obs.cn-south-1.myhuaweicloud.com/latest/tools/chameleon-5.0.0-py3-none-any.whl
chameleon=https://opengauss.obs.cn-south-1.myhuaweicloud.com/latest/tools/${os_name}/chameleon-${portal_version}-${package_arch}.tar.gz
datacheck=https://opengauss.obs.cn-south-1.myhuaweicloud.com/latest/tools/gs_datacheck-${portal_version}.tar.gz
kafka=https://archive.apache.org/dist/kafka/3.2.3/kafka_2.13-3.2.3.tgz
#kafka=https://mirrors.tuna.tsinghua.edu.cn/apache/kafka/3.2.3/kafka_2.13-3.2.3.tgz
confluent=https://packages.confluent.io/archive/5.5/confluent-community-5.5.1-2.12.zip
debezium_connector_mysql=https://opengauss.obs.cn-south-1.myhuaweicloud.com/latest/tools/replicate-mysql2openGauss-${portal_version}.tar.gz
debezium_connector_opengauss=https://opengauss.obs.cn-south-1.myhuaweicloud.com/latest/tools/replicate-openGauss2mysql-${portal_version}.tar.gz

function compress_env_tools() {
    cd ${env_work} | exit 1
    unzip apache-maven-3.6.3-bin.zip
    tar -zxf bisheng-jdk-11.0.19-linux-aarch64.tar.gz
}

function set_env() {
    export ds_tool_home=${env_work}
    export M2_HOME=$ds_tool_home/apache-maven-3.6.3
    export JAVA11_HOME=$ds_tool_home/bisheng-jdk-11.0.19
    export JAVA_HOME=$JAVA11_HOME
    export PATH=$M2_HOME/bin:$JAVA_HOME/bin:$PATH
}

function down_soure_from_gitee() {
    repo=$1
    branch=$2
    target_dir=$3

    a=0
    flag=0
    while [ $a -lt 3 ]; do
        echo $a
        rm -rf ${workspace}/${target_dir}
        timeout 120 git clone ${repo} -b ${branch} "${workspace}/${target_dir}"
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

function down_source() {
    down_soure_from_gitee ${portal_repo} ${giteeTargetBranch} openGauss-migration-portal
}

function mv_pkg() {
    if [[ ! -d ${workspace}/portal_bak ]]; then
        mkdir -p ${workspace}/portal_bak
    fi
    cd ${workspace}/portal_bak
    nums=$(ls -l | grep "^-" | wc -l)
    if [[ $nums = 0 ]]; then
        wget $kafka --no-check-certificate
        wget $confluent --no-check-certificate
    fi
    #cp -r kafka_2.13-3.2.3.tgz  ${workspace}/openGauss-migration-portal/portal/pkg/debezium/
    cp -r confluent-community-5.5.1-2.12.zip ${workspace}/openGauss-migration-portal/portal/pkg/debezium/
}

function mv_config(){
    cd ${workspace}/openGauss-migration-portal/portal/pkg/chameleon
    tar -zxf chameleon-${portal_version}-${package_arch}.tar.gz
    mkdir ${workspace}/openGauss-migration-portal/portal/config/chameleon
    chameleon_config=${workspace}/openGauss-migration-portal/portal/config/chameleon/
    cp -rf chameleon-${portal_version}/venv/lib/python3.6/site-packages/pg_chameleon/configuration/config-example.yml ${chameleon_config}
    rm -rf chameleon-${portal_version}

    cd ${workspace}/openGauss-migration-portal/portal/offline/install
    sh main.sh "openEuler2203_aarch64" ${workspace}/openGauss-migration-portal/portal

    cd ${workspace}/openGauss-migration-portal/portal/pkg/datacheck
    tar -zxf gs_datacheck-${portal_version}.tar.gz
    mkdir ${workspace}/openGauss-migration-portal/portal/config/datacheck
    datacheck_config=${workspace}/openGauss-migration-portal/portal/config/datacheck/
    cp -rf gs_datacheck-${portal_version}/config/* ${datacheck_config}
    rm -rf gs_datacheck-${portal_version}

    cd ${workspace}/openGauss-migration-portal/portal/pkg/debezium
    tar -zxf replicate-mysql2openGauss-${portal_version}.tar.gz
    tar -xzf replicate-openGauss2mysql-${portal_version}.tar.gz
    mkdir ${workspace}/openGauss-migration-portal/portal/config/debezium
    debezium_config=${workspace}/openGauss-migration-portal/portal/config/debezium/
    cp -rf debezium-connector-mysql/mysql-source.properties ${debezium_config}
    cp -rf debezium-connector-mysql/mysql-sink.properties ${debezium_config}
    rm -rf debezium-connector-mysql
    cp -rf debezium-connector-opengauss/opengauss-source.properties ${debezium_config}
    cp -rf debezium-connector-opengauss/opengauss-sink.properties ${debezium_config}
    rm -rf debezium-connector-opengauss
    unzip confluent-community-5.5.1-2.12.zip
    cp -rf confluent-5.5.1/etc/schema-registry/connect-avro-standalone.properties ${debezium_config}
    rm -rf confluent-5.5.1
}

function down_tools() {
    cd ${workspace}/openGauss-migration-portal || exit 1

    mkdir -p portal/pkg/chameleon
    mkdir -p portal/pkg/datacheck
    mkdir -p portal/pkg/debezium

    wget $chameleon -P ${workspace}/openGauss-migration-portal/portal/pkg/chameleon -q
    wget $datacheck -P ${workspace}/openGauss-migration-portal/portal/pkg/datacheck -q
    wget $debezium_connector_mysql -P ${workspace}/openGauss-migration-portal/portal/pkg/debezium -q
    wget $debezium_connector_opengauss -P ${workspace}/openGauss-migration-portal/portal/pkg/debezium -q
    # 拷贝kafka和confluent
    mv_pkg
    mv_config
}

function get_git_log(){
    cd ${workspace}/openGauss-migration-portal/portal
    package_time=`date '+%Y-%m-%d %H:%M:%S'`
    echo "----------------------get_git_log-------------------------"
    echo "build time: "$package_time
    echo "build time: "$package_time >> build_commit_id.log
    echo "git branch: "$(git rev-parse --abbrev-ref HEAD)
    echo "git branch: "$(git rev-parse --abbrev-ref HEAD) >> build_commit_id.log
    echo "last commit:"
	echo "last commit:" >> build_commit_id.log
    echo "$(git log -1)"
    echo "$(git log -1)" >> build_commit_id.log
    echo "----------------------get_git_log finished-------------------------"
}

function package() {
    cd ${workspace}/openGauss-migration-portal || exit 1
    # 修改配置文件中的架构
    sed -i "s/system.arch=x86_64/system.arch=${package_arch}/g" portal/config/toolspath.properties
    sed -i "s/system.name=centos7/system.name=${os_name}/g" portal/config/toolspath.properties
    mvn clean package -Dmaven.test.skip=true

    cp -r target/portalControl-${portal_version}-exec.jar portal/
    cp -r README.md ./portal
    cp -r portal/shell/*.sh portal/
    rm -r portal/shell/
    tar -zcf $portal_package_name portal/
}

function main() {
    yum install -y vim git bzip2 bzip2-devel curl tar zip unzip wget
    #compress_env_tools
    set_env
    down_source
    down_tools
    set_env
    get_git_log
    package
}

main
