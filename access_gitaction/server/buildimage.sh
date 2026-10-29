
docker_image_name=opengauss-ci-x86:ominstall-1.0.1
dockerfile=dockerfile_om_install
docker build -t ${docker_image_name} -f ./${dockerfile} .
docker tag ${docker_image_name} swr.cn-north-4.myhuaweicloud.com/opengauss-ci/${docker_image_name}


### om upgrade
docker_image_name=opengauss-ci-x86:omupgrade-1.0.1
dockerfile=dockerfile_om_upgrade
docker build -t ${docker_image_name} -f ./${dockerfile} .
docker tag ${docker_image_name} swr.cn-north-4.myhuaweicloud.com/opengauss-ci/${docker_image_name}

### llt fastcheck
docker_image_name=opengauss-ci-x86:llt-1.0.1
dockerfile=dockerfile_llt
docker build -t ${docker_image_name} -f ./${dockerfile} .
docker tag ${docker_image_name} swr.cn-north-4.myhuaweicloud.com/opengauss-ci/${docker_image_name}

### ss
docker_image_name=opengauss-ci-x86:ss-1.0.1
dockerfile=dockerfile_ss
docker build -t ${docker_image_name} -f ./${dockerfile} .
docker tag ${docker_image_name} swr.cn-north-4.myhuaweicloud.com/opengauss-ci/${docker_image_name}

### ss-ha
docker_image_name=opengauss-ci-x86:ssha-1.0.1
dockerfile=dockerfile_ss_hatest
docker build -t ${docker_image_name} -f ./${dockerfile} .
docker tag ${docker_image_name} swr.cn-north-4.myhuaweicloud.com/opengauss-ci/${docker_image_name}


### x86 script

### ss-ha
docker_image_name=opengauss-ci-x86:script-1.0.1
dockerfile=dockerfile_script
docker build -t ${docker_image_name} -f ./${dockerfile} .
docker tag ${docker_image_name} swr.cn-north-4.myhuaweicloud.com/opengauss-ci/${docker_image_name}
docker push swr.cn-north-4.myhuaweicloud.com/opengauss-ci/opengauss-ci-x86:script-1.0.1

## upload

docker push swr.cn-north-4.myhuaweicloud.com/opengauss-ci/opengauss-ci-x86:llt-1.0.1
docker push swr.cn-north-4.myhuaweicloud.com/opengauss-ci/opengauss-ci-x86:ominstall-1.0.1
docker push swr.cn-north-4.myhuaweicloud.com/opengauss-ci/opengauss-ci-x86:omupgrade-1.0.1
docker push swr.cn-north-4.myhuaweicloud.com/opengauss-ci/opengauss-ci-x86:ss-1.0.1
docker push swr.cn-north-4.myhuaweicloud.com/opengauss-ci/opengauss-ci-x86:ssha-1.0.1




# arm

docker_image_name=opengauss-ci-arm:llt-1.0.1
dockerfile=dockerfile_llt
docker build -t ${docker_image_name} -f ./${dockerfile} .
docker tag ${docker_image_name} swr.cn-north-4.myhuaweicloud.com/opengauss-ci/${docker_image_name}

## upload
docker push swr.cn-north-4.myhuaweicloud.com/opengauss-ci/opengauss-ci-arm:llt-1.0.1