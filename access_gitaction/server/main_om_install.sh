
docker_name=opengauss-om-install-1.0.0
docker_image_name=opengauss-om-install:1.0.0
dockerfile=dockerfile_om_install
branch_type=master

## build docker images
docker build -t ${docker_image_name} -f ./${dockerfile} .

## run docker images
if [ "$(docker ps -a | grep ${docker_name})" != "" ]; then
    docker rm $docker_name
fi

containerid=`docker run --privileged=true --network=host -d -it -P  -v /etc/localtime:/etc/localtime -e PKG_TYPE=RELEASE  --name ${docker_name} ${docker_image_name} $branch_type`
docker logs -f ${containerid}