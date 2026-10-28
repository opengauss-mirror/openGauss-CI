dockerfile=dockerfile
docker_image_name=opengauss-llt-x86:devarm

docker build -t ${docker_image_name} -f ./${dockerfile} .

docker tag opengauss-llt-x86:devarm swr.cn-north-4.myhuaweicloud.com/opengauss-ci/opengauss-llt-x86:devarm

