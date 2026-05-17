#!/bin/bash
set -xe

# Clone build tools if not present
[ -d build ] || git clone https://gitlab.com/ubports/community-ports/halium-generic-adaptation-build-tools build

# Copy halium.config to kernel source if KERNEL_SRC is set
if [ -n "$KERNEL_SRC" ] && [ -f halium.config ]; then
    echo "Copying halium.config to $KERNEL_SRC/arch/arm64/configs/"
    cp halium.config "$KERNEL_SRC/arch/arm64/configs/"
fi

./build/build.sh "$@"
