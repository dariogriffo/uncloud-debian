uncloud_VERSION=$1
BUILD_VERSION=$2
declare -a arr=("jammy" "noble" "questing")
for i in "${arr[@]}"
do
  UBUNTU_DIST=$i
  FULL_VERSION=$uncloud_VERSION-${BUILD_VERSION}+${UBUNTU_DIST}_amd64_ubu
  docker build . -f Dockerfile.ubu -t uncloud-ubuntu-$UBUNTU_DIST --build-arg UBUNTU_DIST=$UBUNTU_DIST --build-arg uncloud_VERSION=$uncloud_VERSION --build-arg BUILD_VERSION=$BUILD_VERSION --build-arg FULL_VERSION=$FULL_VERSION
  id="$(docker create uncloud-ubuntu-$UBUNTU_DIST)"
  docker cp $id:/uncloud_$FULL_VERSION.deb - > ./uncloud_$FULL_VERSION.deb
  tar -xf ./uncloud_$FULL_VERSION.deb
done
