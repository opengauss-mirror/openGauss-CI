
#!/bin/bash
# Copyright (c) Huawei Technologies Co., Ltd. 2010-2022. All rights reserved.
# description: 
# date: 2022-10-11

set -e

### copy this script under each platform and run to build
docker_name=opengauss-build-001
docker_image_name=opengauss-docker-build:v1
#区分master分支和5.1.0分支
branch_type=$2
current_workspace=$(pwd)
volume_dir=${current_workspace}/opengauss/volume_${branch_type}
tracer_dir=${current_workspace}/opengauss/tracer
root_dir=$(pwd)
remote_test_host=192.168.0.245
VERSION="5.1.0"
os=""
dockerfile="Dockerfile"
obs_upload_path=obs://opengauss/latest
build_log=${current_workspace}/opengauss/log


function log() {
    local level="$1"
    local msg_cont="$2"
    date_time=$(date +'%F %H:%M:%S')

    log_format="${date_time} [${level^^}] funcname: ${FUNCNAME[1]} line:$(caller 0 | awk '{print$1}') ${msg_cont}"
    case "${level}" in
        debug)
            echo -e "${log_format}"
            ;;
        info)
            echo -e "${log_format}"
            ;;
        warn)
            echo -e "${log_format}"
            ;;
        error)
            echo -e "${log_format}"
            ;;
    esac
}

function gen_sha256()
{
    pkg_volume=$1
    cd ${pkg_volume}
    package_list=$(ls *.tar.gz | grep "openGauss" | xargs -n 1 basename)
    for package_name in ${package_list[@]};
    do
        sha256sum -b $package_name > $package_name.sha256
    done
}

function get_os(){
    arch=$(uname -m)
    if [ "X$arch" == "Xaarch64" ]; then
        os="arm"
        dockerfile=${dockerfile}-oelarm
       if [[ "x${volume_dir}" =~ "x/data2" ]]; then
           os=${os}_2203
	   dockerfile=${dockerfile}_2203
       fi
    else
        if [ -f "/etc/openEuler-release" ];then
            os="x86_openEuler"
	    dockerfile=${dockerfile}-oelx86
            if [[ "x${volume_dir}" =~ "x/data2" ]]; then
               os=${os}_2203
	       dockerfile=${dockerfile}_2203
            fi
        else
            os="x86"
            dockerfile=${dockerfile}-x86
        fi
    fi

    echo "${dockerfile}"

}

function uplod_package() {
    if [ X"${branch_type}" == X"5.1.0" ]; then
        obs_upload_path=${obs_upload_path}/5.1.0
    fi
    if [ X"${branch_type}" == X"5.0.0" ]; then
        obs_upload_path=${obs_upload_path}/5.0.0
    fi
    if [ $2 = "debug" ]; then
            obs_upload_path=${obs_upload_path}/debug
    fi
    pkg_volume=$1
    cd ${pkg_volume}
    get_os
    dbs_dest=${os}

    kernel=""
    version=""
    ext_version=""
    dist_version=""
    if [ -f "/etc/euleros-release" ]; then
        kernel=$(cat /etc/euleros-release | awk -F ' ' '{print $1}' | tr A-Z a-z)
        version=$(cat /etc/euleros-release | awk -F '(' '{print $2}'| awk -F ')' '{print $1}' | tr A-Z a-z)
        ext_version=$version
    elif [ -f "/etc/openEuler-release" ]; then
        kernel=$(cat /etc/openEuler-release | awk -F ' ' '{print $1}' | tr A-Z a-z)
        version=$(cat /etc/openEuler-release | awk -F '(' '{print $2}'| awk -F ')' '{print $1}' | tr A-Z a-z)
    elif [ -f "/etc/centos-release" ]; then
        kernel=$(cat /etc/centos-release | awk -F ' ' '{print $1}' | tr A-Z a-z)
        version=$(cat /etc/centos-release | awk -F '(' '{print $2}'| awk -F ')' '{print $1}' | tr A-Z a-z)
    else
        kernel=$(lsb_release -d | awk -F ' ' '{print $2}'| tr A-Z a-z)
        version=$(lsb_release -r | awk -F ' ' '{print $2}')
    fi

    if [ X"$kernel" == X"euleros" ]; then
        dist_version="EULER"
    elif [ X"$kernel" == X"centos" ]; then
        dist_version="CentOS"
    elif [ X"$kernel" == X"openeuler" ]; then
        dist_version="openEuler"
    else
        echo "Only support EulerOS|Centos|openEuler platform."
        echo "Kernel is $kernel"
        exit 1
    fi

    local upload_log=upload.log
    local upload_1_log=upload_1.log
    rm -rf ${upload_log}
    rm -rf ${upload_1_log}

    package_list=$(ls *.tar.gz | grep "openGauss" | xargs -n 1 basename)
    package_num=$(ls *.tar.gz | grep "openGauss" | wc -l)
    for package_name in ${package_list[@]};
    do
        sha256sum -b $package_name > $package_name.sha256
        push_command1="/home/obsutil cp ${package_name} ${obs_upload_path}/${dbs_dest}/"
        push_command2="/home/obsutil cp ${package_name}.sha256 ${obs_upload_path}/${dbs_dest}/"
        set +e
        $push_command1 | tee -a $upload_log
        $push_command2 | tee -a $upload_log
    done

    # upload server for simpleinstall
    local upload_2_log=upload_2.log
    rm -rf ${upload_2_log}
    server_list=$(ls ${pkg_volume} | grep "openGauss" |grep -E "*.bz2|64bit.sha256"| xargs -n 1 basename)
    for ser_name in ${server_list[@]};
    do
        push_command1="/home/obsutil cp ${pkg_volume}/${ser_name} ${obs_upload_path}/${dbs_dest}/"
        $push_command1 | tee -a $upload_2_log
    done

    push_command_git="/home/obsutil cp git_num.txt ${obs_upload_path}/${dbs_dest}/"
    $push_command_git | tee -a $upload_1_log

    set -e
    if [ -f $upload_log ]; then
        # 值为1表示编译成功
        is_uload_package_success=$(grep "Upload successfully" $upload_log | wc -l)
        if [ $is_uload_package_success -eq $((package_num*2)) ]; then
            log 'info' 'upload package to obs successfully '
        else
            log 'error' 'upload package to obs failed'
            exit 1
        fi
    else
        log 'error' 'not generate upload.log upload package to obs failed'
        exit 1
    fi
}

# 构建容器镜像
# 对于三方库有修改（临时，后面三方库一起编译）、构建脚本有修改的需要重新打镜像。
function build_docker_image()
{
    docker build -t ${docker_image_name} -f ./${dockerfile} . 
    if [ $? -ne 0 ]; then
        echo "build opengauss-build image failed.."
        exit 1
    fi
}

function clean_docker_instance()
{
    # rm normal container
    container_ids=$(docker ps | grep ${docker_name} | awk '{print $1}')
    if [ "${container_ids}" != "" ]; then
        docker kill ${container_ids} && docker rm ${container_ids}
    fi

    # rm abnormal container
    abn_container_ids=$(docker ps -a | grep ${docker_name} | awk '{print $1}')
    if [ "${abn_container_ids}" != "" ]; then
        docker rm ${abn_container_ids}
    fi

    # rm none docker images
    non_image_ids=$(docker images | grep none | awk '{print $3}')
    if [ "${non_image_ids}" != "" ]; then
        docker rmi -f ${non_image_ids}
    fi

    #rm exited container
    exited_container_ids=$(docker ps -a|grep Exited|awk '{print $1}')
    if [ "${exited_container_ids}" != "" ]; then
	docker rm ${exited_container_ids}
    fi
}

function send_pkg_to_test()
{
    arch="CentOS"
    if [ ! -f /etc/centos-release ]; then
        arch="openEuler"
    fi
    coretype=$(uname -p)

    cd ${volume_dir}
    package_list=$(ls | grep "openGauss")
    for file in ${package_list[@]};
    do
        set +x
        sshpass -p "paswswd" scp "$file" "root@${remote_test_host}:/data/packages/opengauss/"
        set -x
    done
    
    cd ${tracer_dir}
    cd openGauss-${VERSION}-${arch}-${coretype}-Python.tar.gz
    tracer_list=$(ls | grep *tar.gz)
    for file in ${tracer_list[@]};
    do
        set +x
        sshpass -p "paswswd" scp "$file" "root@${remote_test_host}:/data/packages/opengauss/"
        set -x
    done

    cd ../openGauss-${VERSION}-JDBC.tar.gz
    tracer_list=$(ls | grep *tar.gz)
    for file in ${tracer_list[@]};
    do
        set +x
        sshpass -p "paswswd" scp "$file" "root@${remote_test_host}:/data/packages/opengauss/"
        set -x
    done
}


function trigger_remote_upload()
{
    sshpass -p "paswswd" ssh root@${remote_test_host} "cd /data/packages; sh upload.sh /data/packages/opengauss"
}



function main()
{
    if [ $1 = "debug" ]; then
        pkg_type=debug
        volume_dir=${volume_dir}_debug
    else
        pkg_type=release
    fi

    if [ -d "${volume_dir}" ]; then
        rm -rf ${volume_dir}
    fi
    mkdir -p ${volume_dir}

    get_os

    clean_docker_instance
    build_docker_image

    containerid=`docker run --privileged=true -d -it -P -v ${volume_dir}:/usr1/build/workspace/volume -v /etc/localtime:/etc/localtime -v ${tracer_dir}:/usr1/build/workspace/tracer/ -v ${build_log}:/usr1/build/workspace/log/ -e PKG_TYPE=${pkg_type}  --name ${docker_name} ${docker_image_name} $branch_type`
    docker logs -f ${containerid}

    echo "build opengauss finished......"
    echo "show build files......"
    ls -l ${volume_dir}

    if [ $(ls ${volume_dir} |grep openGauss |wc -l) -gt 0 ]; then
	    uplod_package ${volume_dir} ${pkg_type}
	    cd $root_dir
	    if [ X"${branch_type}" == X"master" ]; then
                sh storeTestVersion.sh ${volume_dir} ${pkg_type} ${branch_type}
            fi
    fi
}

main $@

