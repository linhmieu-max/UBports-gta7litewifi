#!/bin/bash

HALIUM_ANDROID_ROOT=/android
MOUNT_OPTIONS="noatime,nosuid,nodev,barrier=1"

# Tạo thư mục mount nếu chưa có
mkdir -p $HALIUM_ANDROID_ROOT/vendor

# Tiến hành mount phân vùng vendor thực tế của Tab A7 Lite vào hệ thống
mount -o $MOUNT_OPTIONS /dev/block/by-name/vendor $HALIUM_ANDROID_ROOT/vendor

# Một số máy Samsung cần mount thêm phân vùng odm (nếu máy của bạn có phân vùng này)
if [ -b /dev/block/by-name/odm ]; then
    mkdir -p $HALIUM_ANDROID_ROOT/odm
    mount -o $MOUNT_OPTIONS /dev/block/by-name/odm $HALIUM_ANDROID_ROOT/odm
fi

exit 0
