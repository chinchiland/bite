#!/bin/bash
# Puts the Swift toolchain on the PATH inside WSL Ubuntu, without touching system packages.
# One-time setup (already done on this PC):
#   mkdir -p ~/toolchains/debs && cd ~/toolchains
#   curl -sSLO https://download.swift.org/swift-6.4.0-release/ubuntu2404/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE-ubuntu24.04.tar.gz
#   tar xzf swift-6.4.0-RELEASE-ubuntu24.04.tar.gz
#   cd debs && apt-get download libncurses6
# Then: source tools/wsl-swift-env.sh && bash tools/check.sh
TC=~/toolchains/swift-6.4.0-RELEASE-ubuntu24.04
if [ ! -d ~/toolchains/ncurses ]; then
  dpkg -x ~/toolchains/debs/libncurses6_*.deb ~/toolchains/ncurses
fi
export LD_LIBRARY_PATH=~/toolchains/ncurses/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}
export PATH=$TC/usr/bin:$PATH
