![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/dariogriffo/uncloud-debian/total)
![GitHub Downloads (all assets, latest release)](https://img.shields.io/github/downloads/dariogriffo/uncloud-debian/latest/total)
![GitHub Release](https://img.shields.io/github/v/release/dariogriffo/uncloud-debian)
![GitHub Release Date](https://img.shields.io/github/release-date/dariogriffo/uncloud-debian)

<h1>
   <p align="center">
     <a href="https://uncloud.org/"><img src="https://github.com/dariogriffo/uncloud-debian/blob/main/uncloud-logo.png" alt="uncloud Logo" width="128" style="margin-right: 20px"></a>
     <a href="https://www.debian.org/"><img src="https://github.com/dariogriffo/uncloud-debian/blob/main/debian-logo.png" alt="Debian Logo" width="104" style="margin-left: 20px"></a>
     <br>uncloud for Debian
   </p>
</h1>
<p align="center">
 Uncloud is a lightweight clustering and container orchestration tool that lets you deploy and manage web apps across cloud VMs and bare metal with minimised cluster management overhead. It creates a secure WireGuard mesh network between your Docker hosts and provides automatic service discovery, load balancing, ingress with HTTPS, and simple CLI commands to manage your apps.
</p>

# uncloud for Debian

This repository contains build scripts to produce the _unofficial_ Debian packages
(.deb) for [uncloud](https://github.com/psviderski/uncloud/) hosted at [debian.griffo.io](https://debian.griffo.io)

Currently supported debian distros are:
- Bookworm
- Trixie
- Sid

This is an unofficial community project to provide a package that's easy to
install on Debian. If you're looking for the uncloud source code, see
[uncloud](https://github.com/psviderski/uncloud/).

## Install/Update

### The Debian way

```sh
curl -sS https://debian.griffo.io/EA0F721D231FDD3A0A17B9AC7808B4DD62C41256.asc | gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/debian.griffo.io.gpg
echo "deb https://debian.griffo.io/apt $(lsb_release -sc 2>/dev/null) main" | sudo tee /etc/apt/sources.list.d/debian.griffo.io.list
sudo apt install -y uncloud
sudo apt install -y docker-pussh
```

### Manual Installation

1. Download the .deb package for your Debian version available on
   the [Releases](https://github.com/dariogriffo/uncloud-debian/releases) page.
2. Install the downloaded .deb package.

```sh
sudo dpkg -i <filename>.deb
```
## Updating

To update to a new version, just follow any of the installation methods above. There's no need to uninstall the old version; it will be updated correctly.

## Roadmap

- [x] Produce a .deb package on GitHub Releases
- [x] Set up a debian mirror for easier updates

## Disclaimer

- This repo is not open for issues related to uncloud. This repo is only for _unofficial_ Debian packaging.
