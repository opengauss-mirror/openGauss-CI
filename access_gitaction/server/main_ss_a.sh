
docker_name=opengauss-ss-1.0.0
docker_image_name=opengauss-ss:1.0.0
dockerfile=dockerfile_ss
## build docker images

docker build -t ${docker_image_name} -f ./${dockerfile} .

## run docker images
if [ "$(docker ps -a | grep ${docker_name})" != "" ]; then
    docker rm $docker_name
fi

containerid=`docker run kernel.sem="250 6400000 1000 25600" --privileged=true --network=host -d -it -P  -v /etc/localtime:/etc/localtime -e PKG_TYPE=DEBUG --name ${docker_name} ${docker_image_name}`
docker logs -f ${containerid}