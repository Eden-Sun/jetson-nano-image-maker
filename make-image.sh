image_name=jetson-nano-rootfs-image

docker build --platform linux/arm64 -t $image_name ./target

conatiner_name=temp-container

docker export $(docker create --name $conatiner_name $image_name) -o rootfs.tar
docker rm $conatiner_name


builder_image_name=jetson-nano-builder
docker build --platform linux/arm64 -t $builder_image_name ./packager

docker run --rm -v $(pwd):/host --privileged $builder_image_name