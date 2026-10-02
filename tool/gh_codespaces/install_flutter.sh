#!/bin/bash

# Copyright (C) 2023-2024 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# install_flutter.sh
# GitHub Codespaces setup: Install Flutter SDK following this Dockerfile recipe:
#    https://github.com/appleboy/flutter-docker/blob/master/Dockerfile
# or this git area
#    https://github.com/yostane/flutter2-desktop
#
# 2024 February 12
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

set -euo pipefail

flutter_version='3.47.2'

flutter_archive="/tmp/flutter_linux_${flutter_version}-stable.tar.xz"
flutter_url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${flutter_version}-stable.tar.xz"

wget -O "$flutter_archive" "$flutter_url"

# If running as root, install to /usr/local (typical for container images). If
# running as a regular user, extract to $HOME/flutter to avoid needing sudo.
if [ "$(id -u)" -eq 0 ]; then
	echo "Installing Flutter to /usr/local/flutter (running as root)"
	cd /usr/local
	tar -xf "$flutter_archive"
	profile_path="/etc/profile.d/flutter.sh"
	echo 'export PATH="/usr/local/flutter/bin:$PATH"' > "$profile_path"
	echo "Wrote PATH to $profile_path"
else
	echo "Installing Flutter to $HOME/flutter (no sudo required)"
	mkdir -p "$HOME/flutter"
	tar -xf "$flutter_archive" -C "$HOME"
	# Add to user's bashrc
	echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.bashrc
fi

rm "$flutter_archive"
