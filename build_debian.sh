uncloud_VERSION=$1
BUILD_VERSION=$2
declare -a arr=("bookworm" "trixie" "sid")
for i in "${arr[@]}"
do
  DEBIAN_DIST=$i
  FULL_VERSION=$uncloud_VERSION-${BUILD_VERSION}+${DEBIAN_DIST}_amd64
  docker build . -t uncloud-$DEBIAN_DIST  --build-arg DEBIAN_DIST=$DEBIAN_DIST --build-arg uncloud_VERSION=$uncloud_VERSION --build-arg BUILD_VERSION=$BUILD_VERSION --build-arg FULL_VERSION=$FULL_VERSION
  id="$(docker create uncloud-$DEBIAN_DIST)"
  docker cp $id:/uncloud_$FULL_VERSION.deb - > ./uncloud_$FULL_VERSION.deb
  tar -xf ./uncloud_$FULL_VERSION.deb
done


