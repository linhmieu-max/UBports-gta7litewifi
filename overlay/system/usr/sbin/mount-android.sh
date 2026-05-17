#!/bin/bash

# RW root
mount -o remount,rw /

# A/B slot detect
ab_slot_suffix=$(grep -o 'androidboot\.slot_suffix=[^ ]*' /proc/cmdline | cut -d "=" -f2)
[ ! -z "$ab_slot_suffix" ] && echo "A/B slot detected: $ab_slot_suffix"

find_partition_path() {
    label=$1
    path="/dev/$label"
    for dir in by-partlabel by-name by-label by-path by-uuid by-partuuid by-id; do
        if [ -e "/dev/disk/$dir/$label$ab_slot_suffix" ]; then
            path="/dev/disk/$dir/$label$ab_slot_suffix"
            break
        elif [ -e "/dev/disk/$dir/$label" ]; then
            path="/dev/disk/$dir/$label"
            break
        fi
    done
    echo $path
}

parse_mount_flags() {
    org_options="$1"
    options=""
    for i in $(echo $org_options | tr "," "\n"); do
        [[ "$i" =~ "context" ]] && continue
        options+=$i","
    done
    options=${options%?}
    echo $options
}

echo "=== Mount Android partitions ==="

# Mount system
if ! mountpoint -q /android/system; then
    mkdir -p /android/system
    system_path=$(find_partition_path "system")
    echo "Mounting $system_path -> /android/system"
    mount -o ro "$system_path" /android/system || echo "FAIL system mount"
fi

# Mount vendor
if ! mountpoint -q /android/vendor; then
    mkdir -p /android/vendor
    vendor_path=$(find_partition_path "vendor")
    echo "Mounting $vendor_path -> /android/vendor"
    mount -o ro "$vendor_path" /android/vendor || echo "FAIL vendor mount"
fi

# Mount product partition if present (needed for some MTK blobs)
if ! mountpoint -q /android/product; then
    mkdir -p /android/product
    product_path=$(find_partition_path "product")
    if [ -e "$product_path" ]; then
        echo "Mounting $product_path -> /android/product"
        mount -o ro "$product_path" /android/product || echo "INFO: product mount skipped"
    fi
fi

# DEBUG
ls /android/system/lib64 2>/dev/null | head -5 || echo "system lib64 missing"
ls /android/vendor/lib64 2>/dev/null | head -5 || echo "vendor lib64 missing"

# Bind for LXC container
mkdir -p /var/lib/lxc/android/rootfs/system
mkdir -p /var/lib/lxc/android/rootfs/vendor
mkdir -p /var/lib/lxc/android/rootfs/product

mount --bind /android/system /var/lib/lxc/android/rootfs/system
mount --bind /android/vendor /var/lib/lxc/android/rootfs/vendor
if mountpoint -q /android/product; then
    mount --bind /android/product /var/lib/lxc/android/rootfs/product
fi

echo "=== Mount done ==="

# APEX - only mount if directory exists and has contents
if [ -d "/android/system/apex" ]; then
    mkdir -p /apex
    mount -t tmpfs tmpfs /apex 2>/dev/null || true
    for apex_path in \
        "/android/system/apex/com.android.runtime.release.apex" \
        "/android/system/apex/com.android.runtime.debug.apex" \
        "/android/system/apex/com.android.runtime.release" \
        "/android/system/apex/com.android.runtime.debug"; do
        if [ -e "$apex_path" ]; then
            mkdir -p /apex/com.android.runtime
            mount -o bind "$apex_path" /apex/com.android.runtime 2>/dev/null || true
            break
        fi
    done
fi

# Bind Android libs into hybris paths so libhybris can find them
HYBRIS_DIR=/usr/lib/aarch64-linux-gnu/hybris
mkdir -p "$HYBRIS_DIR/system_lib64" "$HYBRIS_DIR/vendor_lib64"

if [ -d /android/system/lib64 ]; then
    mount --bind /android/system/lib64 "$HYBRIS_DIR/system_lib64" 2>/dev/null || echo "bind system lib64 failed"
fi

if [ -d /android/vendor/lib64 ]; then
    mount --bind /android/vendor/lib64 "$HYBRIS_DIR/vendor_lib64" 2>/dev/null || echo "bind vendor lib64 failed"
fi

# Write Android props to a file for init.halium to source
# (setprop cannot run here - property_service not started yet)
mkdir -p /run/halium
cat > /run/halium/android-props.sh << 'EOF'
export HYBRIS_EGLPLATFORM=hwcomposer
export EGL_PLATFORM=hwcomposer
export ANDROID_ROOT=/android/system
export ANDROID_DATA=/android/data
export ANDROID_STORAGE=/android/storage
EOF

echo "=== mount-android.sh done ==="
