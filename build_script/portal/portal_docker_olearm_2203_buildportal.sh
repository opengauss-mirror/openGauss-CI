#!/bin/bash
docker_name=portal-001
docker_image_name=portal-docker-oel2203-arm:v1
volume_dir=/data2/autobuild/portal
obs_upload_path=obs://opengauss/latest/tools
version=7.0.0rc1
package_arch=$(uname -p)

function clean_docker_instance() {
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
}

function build_docker_image() {
    echo "docker build -t ${docker_image_name} ."
    docker build -t ${docker_image_name} .
    if [ $? -ne 0 ]; then
        echo "build ${docker_image_name} image failed.."
        exit 1
    fi
}

function run_docker_container() {
    echo "docker run --privileged=true -d -it -P -v ${volume_dir}:${volume_dir} --name ${docker_name} ${docker_image_name}"
    containerid=$(docker run --privileged=true -dit -P -v ${volume_dir}:${volume_dir} --name ${docker_name} ${docker_image_name})
    if [[ $? -ne 0 ]]; then
        echo "run ${docker_name} failed!"
        exit 1
    fi
}

function upload_obs() {
    cd ${volume_dir}/openGauss-migration-portal || exit 1

    os_name=$(
        source /etc/os-release
        echo ${ID}22.03
    )

    local upload_log=upload.log
    rm -rf ${upload_log}

    generate_date=$(date +"%Y%m%d")
    clear_date=$(date +"%Y%m%d" -d "-7 days")
    package_generate_date_name=PortalControl-${version}-${package_arch}-${generate_date}.tar.gz
    package_clear_date_name=PortalControl-${version}-${package_arch}-${clear_date}.tar.gz

    package_list=$(ls ./*.tar.gz | grep "Portal" | xargs -n 1 basename)
    package_num=$(ls ./*.tar.gz | grep "Portal" | wc -l)
    for package_name in "${package_list[@]}"; do
        sha256sum -b $package_name >$package_name.sha256
        echo "https://opengauss.obs.cn-south-1.myhuaweicloud.com/latest/tools/${os_name}/${package_name}"
        push_command1="/home/obsutil cp ${package_name} ${obs_upload_path}/${os_name}/"
        echo "https://opengauss.obs.cn-south-1.myhuaweicloud.com/latest/tools/${os_name}/${package_name}.sha256"
        push_command2="/home/obsutil cp ${package_name}.sha256 ${obs_upload_path}/${os_name}/"
        push_command3="/home/obsutil cp ${package_name} ${obs_upload_path}/${os_name}/${package_generate_date_name}"
        push_command4="/home/obsutil cp ${package_name}.sha256 ${obs_upload_path}/${os_name}/${package_generate_date_name}.sha256"

        push_command5="/home/obsutil rm ${obs_upload_path}/${os_name}/${package_clear_date_name}"
        push_command6="/home/obsutil rm ${obs_upload_path}/${os_name}/${package_clear_date_name}.sha256"

        $push_command1 | tee -a $upload_log
        $push_command2 | tee -a $upload_log
        $push_command3 | tee -a $upload_log
        $push_command4 | tee -a $upload_log
        $push_command5 | tee -a $upload_log
        $push_command6 | tee -a $upload_log
    done

    if [ -f $upload_log ]; then
        # 值为1表示编译成功
        is_upload_package_success=$(grep "Upload successfully" $upload_log | wc -l)
        if [ $is_upload_package_success -eq $((package_num * 4)) ]; then
            echo 'info upload package to obs successfully '
        else
            echo 'error upload package to obs failed'
            exit 1
        fi
    else
        echo 'error not generate upload.log upload package to obs failed'
        exit 1
    fi
}

function main() {
    clean_docker_instance
    build_docker_image
    run_docker_container
    docker logs -f ${containerid}
    upload_obs
}

main $@