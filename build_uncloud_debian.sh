uncloud_VERSION=$1
BUILD_VERSION=$2
ARCH=${3:-amd64}

if [ -z "$uncloud_VERSION" ] || [ -z "$BUILD_VERSION" ]; then
    echo "Usage: $0 <uncloud_version> <build_version> [architecture]"
    echo "Example: $0 0.18.0 1 arm64"
    echo "Example: $0 0.18.0 1 all    # Build for all architectures"
    echo "Supported architectures: amd64, arm64"
    exit 1
fi

get_uncloud_arch() {
    local arch=$1
    case "$arch" in
        "amd64")
            echo "amd64"
            ;;
        "arm64")
            echo "arm64"
            ;;
        *)
            echo ""
            ;;
    esac
}

build_architecture() {
    local build_arch=$1
    local release_arch

    release_arch=$(get_uncloud_arch "$build_arch")
    if [ -z "$release_arch" ]; then
        echo "❌ Unsupported architecture: $build_arch"
        echo "Supported architectures: amd64, arm64"
        return 1
    fi

    echo "Building for architecture: $build_arch"

    declare -a arr=("bookworm" "trixie" "forky" "sid")

    for dist in "${arr[@]}"; do
        FULL_VERSION="$uncloud_VERSION-${BUILD_VERSION}+${dist}_${build_arch}"
        echo "  Building uncloud $FULL_VERSION"

        rm -f "uncloud_linux_${release_arch}.tar.gz"
        if ! wget "https://github.com/psviderski/uncloud/releases/download/v${uncloud_VERSION}/uncloud_linux_${release_arch}.tar.gz"; then
            echo "❌ Failed to download uncloud binary for $build_arch"
            return 1
        fi
        mkdir -p "build/${build_arch}"
        tar -xzf "uncloud_linux_${release_arch}.tar.gz" -C "build/${build_arch}"
        rm -f "uncloud_linux_${release_arch}.tar.gz"

        if ! docker build . -f uncloud_Dockerfile -t "uncloud-$dist-$build_arch" \
            --build-arg uncloud_VERSION="$uncloud_VERSION" \
            --build-arg DEBIAN_DIST="$dist" \
            --build-arg BUILD_VERSION="$BUILD_VERSION" \
            --build-arg FULL_VERSION="$FULL_VERSION" \
            --build-arg ARCH="$build_arch"; then
            echo "❌ Failed to build Docker image for uncloud $dist on $build_arch"
            rm -rf "build/${build_arch}"
            return 1
        fi

        id="$(docker create "uncloud-$dist-$build_arch")"
        docker cp "$id:/uncloud_$FULL_VERSION.deb" - > "./uncloud_$FULL_VERSION.deb"
        tar -xf "./uncloud_$FULL_VERSION.deb"
        rm -rf "build/${build_arch}"

        echo "  Building uncloudd $FULL_VERSION"

        rm -f "uncloudd_linux_${release_arch}.tar.gz"
        if ! wget "https://github.com/psviderski/uncloud/releases/download/v${uncloud_VERSION}/uncloudd_linux_${release_arch}.tar.gz"; then
            echo "❌ Failed to download uncloudd binary for $build_arch"
            return 1
        fi
        mkdir -p "build/${build_arch}"
        tar -xzf "uncloudd_linux_${release_arch}.tar.gz" -C "build/${build_arch}"
        rm -f "uncloudd_linux_${release_arch}.tar.gz"

        if ! docker build . -f uncloudd_Dockerfile -t "uncloudd-$dist-$build_arch" \
            --build-arg uncloud_VERSION="$uncloud_VERSION" \
            --build-arg DEBIAN_DIST="$dist" \
            --build-arg BUILD_VERSION="$BUILD_VERSION" \
            --build-arg FULL_VERSION="$FULL_VERSION" \
            --build-arg ARCH="$build_arch"; then
            echo "❌ Failed to build Docker image for uncloudd $dist on $build_arch"
            rm -rf "build/${build_arch}"
            return 1
        fi

        id="$(docker create "uncloudd-$dist-$build_arch")"
        docker cp "$id:/uncloudd_$FULL_VERSION.deb" - > "./uncloudd_$FULL_VERSION.deb"
        tar -xf "./uncloudd_$FULL_VERSION.deb"
        rm -rf "build/${build_arch}"
    done

    echo "✅ Successfully built for $build_arch"
    return 0
}

if [ "$ARCH" = "all" ]; then
    echo "🚀 Building uncloud $uncloud_VERSION-$BUILD_VERSION for all supported architectures..."
    echo ""

    ARCHITECTURES=("amd64" "arm64")

    for build_arch in "${ARCHITECTURES[@]}"; do
        echo "==========================================="
        echo "Building for architecture: $build_arch"
        echo "==========================================="

        if ! build_architecture "$build_arch"; then
            echo "❌ Failed to build for $build_arch"
            exit 1
        fi

        echo ""
    done

    echo "🎉 All architectures built successfully!"
    echo "Generated packages:"
    ls -la uncloud_*.deb uncloudd_*.deb
else
    if ! build_architecture "$ARCH"; then
        exit 1
    fi
fi
