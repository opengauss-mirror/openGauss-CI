#!/bin/bash
#WORKSPACE=/var/jenkins_home/workspace/datakit-build

if [ "${branch}" == "" ]; then
    branch=master
fi

VERSION=5.0.0

echo "###### build openGauss-workbench(Datakit) ######"
export ds_tool_home=/home/dstools
export M2_HOME=$ds_tool_home/apache-maven-3.6.3
export JAVA8_HOME=$ds_tool_home/jdk1.8.0_311
export JAVA11_HOME=$ds_tool_home/jdk-11.0.2
export JAVA_HOME=$JAVA11_HOME
export NODE_HOME=/home/dstools/node-v16.15.1-linux-x64
export PATH=$M2_HOME/bin:$JAVA_HOME/bin:$NODE_HOME/bin:$PATH

workbench_repo=https://gitee.com/opengauss/openGauss-workbench.git
workbench_branch=${branch}
workbench_base=workbench
repo_dir=$WORKSPACE/$workbench_base
pkg_dir=$WORKSPACE/$workbench_base/output

function download_from_gitee() {
    repo=$1
    branch=$2
    target_dir=$3
    if [ -d ${target_dir} ]; then
        rm -rf ${target_dir}
    fi
    echo "download source [${repo}], branch [${branch}]"

    git config --global core.compression 0
    a=0
    flag=0
    while [ $a -lt 3 ]
    do
    echo $a
    timeout 120 git clone ${repo} -b ${branch} ${target_dir}
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

if [ -d ${workbench_base} ]; then
   rm -rf ${workbench_base}
fi

download_from_gitee ${workbench_repo} ${workbench_branch} ${workbench_base}
mkdir -p $pkg_dir

function build_plugins(){
    cd ${repo_dir}/plugins
    echo "----------------------------------------------------data-studio---------------------------------------------"
    cd ./data-studio
    mvn clean package -P prod
    if [ $? -ne 0 ]; then
        echo "Build data-studio failed..."
        exit 1
    fi
    cp ./target/*repackage.jar ${pkg_dir}/
    cp ./readme.md ${pkg_dir}/data-studio-readme.md

    echo "-------------------------------------------------observability-instance-------------------------------------"
    cd ../observability-instance
    mvn clean package -P prod
    if [ $? -ne 0 ]; then
        echo "Build observability-instance failed..."
        exit 1
    fi
    cp ./target/*repackage.jar ${pkg_dir}/
    cp ./README.md ${pkg_dir}/observability-instance-README.md
    
    echo "------------------------------------------------observability-log-search-------------------------------------"
    cd ../observability-log-search
    mvn clean package -P prod
    if [ $? -ne 0 ]; then
        echo "Build observability-log-search failed..."
        exit 1
    fi
    cp ./target/*repackage.jar ${pkg_dir}/
    cp README.md ${pkg_dir}/observability-log-search-README.md

    echo "-----------------------------------------observability-sql-diagnosis-----------------------------------------"
    cd ../observability-sql-diagnosis
    mvn clean package -P prod
    if [ $? -ne 0 ]; then
        echo "Build observability-log-search failed..."
        exit 1
    fi
    cp ./target/*repackage.jar ${pkg_dir}/
    cp README.md ${pkg_dir}/observability-sql-diagnosis-README.md
}



function build_pkg(){
    cd ${repo_dir}/openGauss-visualtool
    mvn clean install -P prod -Dmaven.test.skip=true
    if [ $? -ne 0 ]; then
        echo "Build visualtool failed..."
        exit 1
    fi
    cp ./visualtool-api/target/visualtool-main.jar ${pkg_dir}/
    cp ./README.md ${pkg_dir}/visualtool-README.md
    cp ./config/application-temp.yml ${pkg_dir}/     

    cd ${repo_dir}/base-ops
    mvn clean package -Dmaven.test.skip=true
    if [ $? -ne 0 ]; then
        echo "Build base-ops failed..."
        exit 1
    fi
    cp ./target/*repackage.jar ${pkg_dir}/
    cp ./README.md ${pkg_dir}/base-ops-README.md

    cd ${repo_dir}/data-migration
    mvn clean package -Dmaven.test.skip
    if [ $? -ne 0 ]; then
        echo "Build data-migration failed..."
        exit 1
    fi
    cp ./target/*repackage.jar ${pkg_dir}/
    cp ./README.md ${pkg_dir}/data-migration-README.md
    

    build_plugins   
}

build_pkg

cd ${pkg_dir}/ && tar -zcf Datakit-${VERSION}.tar.gz ./*

obsutil cp Datakit-${VERSION}.tar.gz obs://opengauss/latest/tools/Datakit/

echo "Build openGauss-workbench success..."
