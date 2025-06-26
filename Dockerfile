ARG DEBIAN_DIST=bookworm

FROM golang:1.24-alpine AS builder
RUN apk add git

WORKDIR /build
RUN git clone https://github.com/psviderski/uncloud.git

# Download and cache dependencies and only redownload them in subsequent builds if they change.

RUN cd uncloud && go mod download && go mod verify && go build -o uc ./cmd/uncloud

FROM buildpack-deps:$DEBIAN_DIST

ARG DEBIAN_DIST
ARG uncloud_VERSION
ARG BUILD_VERSION
ARG FULL_VERSION

RUN mkdir -p /output/usr/bin/
COPY --from=builder /build/uncloud/uc /output/usr/bin/

COPY packages/uncloud/output/DEBIAN/control /output/DEBIAN/
COPY packages/uncloud/output/copyright /output/usr/share/doc/uncloud/
COPY packages/uncloud/output/changelog.Debian /output/usr/share/doc/uncloud/
COPY packages/uncloud/output/README.md /output/usr/share/doc/uncloud/

RUN sed -i "s/DIST/$DEBIAN_DIST/" /output/usr/share/doc/uncloud/changelog.Debian
RUN sed -i "s/FULL_VERSION/$FULL_VERSION/" /output/usr/share/doc/uncloud/changelog.Debian
RUN sed -i "s/DIST/$DEBIAN_DIST/" /output/DEBIAN/control
RUN sed -i "s/uncloud_VERSION/$uncloud_VERSION/" /output/DEBIAN/control
RUN sed -i "s/BUILD_VERSION/$BUILD_VERSION/" /output/DEBIAN/control

RUN dpkg-deb --build /output /uncloud_${FULL_VERSION}.deb
