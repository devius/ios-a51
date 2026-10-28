#!/bin/bash
# Prepare an Intel macOS 13.5+ machine (e.g. the Docker-OSX VM) to build the A51
# XNU kernel and the iOS tools the way CI does (.github/workflows/xnu.yml,
# ios-tools.yml): jq, gum, bash 5, cmake, ninja, xcodes, and Xcode 15.2 (Xcode 16
# breaks this xnu: its iig emits IORPC.kernelContent).
#
# Homebrew no longer supports Intel Macs, so the tools come from their release
# downloads into /usr/local/bin, which darwin-xnu-build's clean PATH keeps on
# Intel. bash is compiled from GNU's tarball (needs the Command Line Tools).
#
# Run it in a terminal on the Mac as your user; it asks for your password for
# sudo, and xcodes asks for your Apple ID (and a 2FA code) to download Xcode:
#   ./setup-mac-build.sh
# If ~/Downloads/Xcode_15.2.xip is already there, it is used instead.
# Safe to run again: every step is skipped when already done.
set -euo pipefail

say() { printf '\n== %s\n' "$*"; }
bin=/usr/local/bin
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fetch() { curl -fL --retry 3 --max-time 900 -o "$2" "$1"; }

say "0/4 Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1; then
	xcode-select --install || true
	echo "Finish the Command Line Tools installer window, then run this script again."
	exit 1
fi
sudo mkdir -p "$bin"

say "1/4 build tools into $bin"
have() { [[ -x $bin/$1 ]] && echo "  $1: already there"; }
have jq || { fetch https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-macos-amd64 "$tmp/jq"; sudo install -m 755 "$tmp/jq" "$bin/jq"; }
have gum || {
	fetch https://github.com/charmbracelet/gum/releases/download/v0.14.5/gum_0.14.5_Darwin_x86_64.tar.gz "$tmp/gum.tgz"
	tar -xzf "$tmp/gum.tgz" -C "$tmp"
	sudo install -m 755 "$(find "$tmp" -type f -name gum | head -1)" "$bin/gum"
}
have ninja || { fetch https://github.com/ninja-build/ninja/releases/download/v1.12.1/ninja-mac.zip "$tmp/ninja.zip"; unzip -oq "$tmp/ninja.zip" -d "$tmp"; sudo install -m 755 "$tmp/ninja" "$bin/ninja"; }
have xcodes || { fetch https://github.com/XcodesOrg/xcodes/releases/download/1.6.0/xcodes.zip "$tmp/xcodes.zip"; unzip -oq "$tmp/xcodes.zip" -d "$tmp"; sudo install -m 755 "$(find "$tmp" -type f -name xcodes | head -1)" "$bin/xcodes"; }
have cmake || {
	fetch https://github.com/Kitware/CMake/releases/download/v3.30.5/cmake-3.30.5-macos-universal.tar.gz "$tmp/cmake.tgz"
	sudo rm -rf /Applications/CMake.app
	tar -xzf "$tmp/cmake.tgz" -C "$tmp"
	sudo mv "$tmp"/cmake-3.30.5-macos-universal/CMake.app /Applications/
	for t in cmake ctest cpack; do sudo ln -sf /Applications/CMake.app/Contents/bin/$t "$bin/$t"; done
}
have bash || {
	fetch https://ftp.gnu.org/gnu/bash/bash-5.2.37.tar.gz "$tmp/bash.tgz"
	tar -xzf "$tmp/bash.tgz" -C "$tmp"
	(cd "$tmp/bash-5.2.37" && ./configure --prefix=/usr/local --quiet >/dev/null && make -s -j"$(sysctl -n hw.ncpu)" >/dev/null && sudo make -s install >/dev/null)
}

say "2/4 Xcode 15.2"
xcode=$(ls -d /Applications/Xcode*15.2*.app 2>/dev/null | head -1 || true)
if [[ -z $xcode ]]; then
	if [[ -f ~/Downloads/Xcode_15.2.xip ]]; then
		(cd ~/Downloads && xip -x Xcode_15.2.xip)
		sudo mv ~/Downloads/Xcode.app /Applications/Xcode-15.2.app
	else
		echo "xcodes asks for your Apple ID (and a 2FA code) to download Xcode 15.2 (~3 GB)."
		"$bin/xcodes" install 15.2 --experimental-unxip
	fi
	xcode=$(ls -d /Applications/Xcode*15.2*.app | head -1)
fi
echo "using $xcode"

say "3/4 select Xcode, accept the license, first launch"
sudo xcode-select -s "$xcode/Contents/Developer"
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch

say "4/4 check"
xcodebuild -version
echo "iig:        $(xcrun --find iig)"
echo "macOS SDK:  $(xcrun --sdk macosx --show-sdk-path)"
echo "iOS SDK:    $(xcrun --sdk iphoneos --show-sdk-path)"
echo "tools:      jq $($bin/jq --version), gum $($bin/gum --version | awk '{print $3}'), bash $($bin/bash -c 'echo $BASH_VERSION'), cmake $($bin/cmake --version | awk 'NR==1{print $3}'), ninja $($bin/ninja --version), xcodes $($bin/xcodes version 2>/dev/null || echo ok)"
echo
echo "Ready to build the A51 kernel on this Mac."
