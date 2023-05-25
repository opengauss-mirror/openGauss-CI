#!/bin/bash
set -e
WORKSPACE=/data/autobuild
giteeTargetBranch=master
portal_version=5.0.0

portal_repo=https://gitee.com/opengauss/openGauss-migration-portal.git
obs_upload_path=obs://opengauss/latest/tools
portal_package_name=PortalControl-${portal_version}.tar.gz
chameleon=https://opengauss.obs.cn-south-1.myhuaweicloud.com/latest/tools/chameleon-5.0.0-py3-none-any.whl
datacheck=https://opengauss.obs.cn-south-1.myhuaweicloud.com/latest/tools/gs_datacheck-5.0.0.tar.gz
kafka=https://mirrors.tuna.tsinghua.edu.cn/apache/kafka/3.2.3/kafka_2.13-3.2.3.tgz
confluent=https://packages.confluent.io/archive/5.5/confluent-community-5.5.1-2.12.zip
debezium_connector_mysql=https://opengauss.obs.cn-south-1.myhuaweicloud.com/latest/tools/replicate-mysql2openGauss-5.0.0.tar.gz
debezium_connector_opengauss=https://opengauss.obs.cn-south-1.myhuaweicloud.com/latest/tools/replicate-openGauss2mysql-5.0.0.tar.gz
portal_dependency_package_path=/opt/portal/pkg

if [[ ! -d ${WORKSPACE} ]]; then
    mkdir -p ${WORKSPACE}
fi

if [[ ! -d ${portal_dependency_package_path} ]]; then
    mkdir -p ${portal_dependency_package_path}
fi

function down_soure_from_gitee() {
    repo=$1
    branch=$2
    target_dir=$3

    a=0
    flag=0
    while [ $a -lt 3 ]; do
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

function down_source() {
    down_soure_from_gitee ${portal_repo} ${giteeTargetBranch} openGauss-migration-portal
}

function down_tools() {
    wget $chameleon -P ${portal_dependency_package_path}/chameleon
    wget $datacheck -P ${portal_dependency_package_path}/datacheck
    wget $kafka -P ${portal_dependency_package_path}/debezium --no-check-certificate
    wget $confluent -P ${portal_dependency_package_path}/debezium --no-check-certificate
    wget $debezium_connector_mysql -P ${portal_dependency_package_path}/debezium
    wget $debezium_connector_opengauss -P ${portal_dependency_package_path}/debezium
}

function copy_pkg() {
    cd ${WORKSPACE}/openGauss-migration-portal || exit

    mkdir -p portal/pkg/chameleon
    mkdir -p portal/pkg/datacheck
    mkdir -p portal/pkg/debezium
    cp -rf ${portal_dependency_package_path} ${WORKSPACE}/openGauss-migration-portal/portal/
}

function delete_pkg() {
    cd ${portal_dependency_package_path} && rm -rf ./*
}

function is_downed_pkg() {
    # 判断是否已经下载了，如果有直接复制
    if [[ -d ${portal_dependency_package_path} ]]; then
        test -d ${portal_dependency_package_path}/chameleon && chameleon_size=$(ls ${portal_dependency_package_path}/chameleon | wc -l)
        if [[ $chameleon_size -ne 1 ]]; then
            delete_pkg
            down_tools
            return
        fi
        test -d ${portal_dependency_package_path}/datacheck && datacheck_size=$(ls ${portal_dependency_package_path}/datacheck | wc -l)
        if [[ $datacheck_size -ne 1 ]]; then
            delete_pkg
            down_tools
            return
        fi
        test -d ${portal_dependency_package_path}/debezium && debezium_size=$(ls ${portal_dependency_package_path}/debezium | wc -l)
        if [[ $debezium_size -ne 4 ]]; then
            delete_pkg
            down_tools
            return
        fi
    fi
}

function export_env() {
    export JAVA_HOME=/opt/install/jdk-11.0.18
    export PATH=$JAVA_HOME/bin:$PATH
    export MAVEN_HOME=/opt/install/apache-maven-3.8.8
    export PATH=$MAVEN_HOME/bin:$PATH
}

function package() {
    cd ${WORKSPACE}/openGauss-migration-portal || exit
    mvn clean package -Dmaven.test.skip=true

    cp -r target/portalControl-1.0-SNAPSHOT-exec.jar portal/
    cp -r README.md ./portal
    cp -r portal/shell/*.sh portal/
    rm -r portal/shell/
    tar -zcf $portal_package_name portal/
}

function upload_obs() {
    cd ${WORKSPACE}/openGauss-migration-portal || exit

    local upload_log=upload.log
    rm -rf ${upload_log}

    package_list=$(ls ./*.tar.gz | grep "Portal" | xargs -n 1 basename)
    package_num=$(ls ./*.tar.gz | grep "Portal" | wc -l)
    for package_name in "${package_list[@]}"; do
        sha256sum -b $package_name >$package_name.sha256
        push_command1="obsutil cp ${package_name} ${obs_upload_path}/"
        push_command2="obsutil cp ${package_name}.sha256 ${obs_upload_path}/"

        $push_command1 | tee -a $upload_log
        $push_command2 | tee -a $upload_log
    done

    if [ -f $upload_log ]; then
        # 值为1表示编译成功
        is_upload_package_success=$(grep "Upload successfully" $upload_log | wc -l)
        if [ $is_upload_package_success -eq $((package_num * 2)) ]; then
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
    is_downed_pkg
    copy_pkg
    export_env
    package
    upload_obs
    exit 0
}

main "$@"
