# Changelog v2 — fixes từ log phân tích thực tế
# Nguồn: /var/log/lightdm/unity-system-compositor.log + systemd journal
# Ngày log: 2025-01-08 13:54 → 13:57

---

## [CRITICAL] bluetooth.service: "Service has no ExecStart" → 457 bluebinder crashes

**File:** `etc/systemd/system/bluetooth.service`
**Log:**
```
bluetooth.service: Service has no ExecStart=, ExecStop=, or SuccessAction=. Refusing.
bluebinder: g_io_channel_shutdown: assertion 'channel != NULL' failed
[×457 lần / ~3 phút]
```
**Nguyên nhân:** File override cũ chỉ có `[Unit]` section, không có `[Service]` block → systemd từ chối unit → bluebinder không có bluetooth service để kết nối → crash-restart mỗi 4–5 giây → 457 crash trong log → tiêu tốn CPU đáng kể, làm chậm toàn bộ boot pipeline.

**Sửa:** Thêm `[Service]` block hợp lệ với `ExecStart=/bin/true` + `RemainAfterExit=yes`. Systemd chấp nhận unit, bluebinder stop crash loop.

---

## [CRITICAL] USC crash: dequeueBuffer broken_promise → signal 11 (SIGSEGV)

**File:** `etc/default/lsc-wrapper.d/10-force-hwc2.conf`
**Log:**
```
ERROR AndroidWindow: dequeueBuffer: broken_promise
ERROR MirConnectionAPI: Failed to send message: Broken pipe
Can't eglMakeCurrent
Process 2088 terminated with signal 11
```
**Nguyên nhân:** USC (lomiri-system-compositor) khởi động thành công (EGL lên, PowerVR GE8320 nhận đúng, display 800×1340), nhưng sau ~3 phút crash khi Lomiri client gọi `dequeueBuffer`. USC không thể dequeue buffer → broken promise → pipe đứt → SIGSEGV. Root cause: buffer queue depth mismatch giữa USC và PowerVR gralloc, + USC cố tìm `libminisf.so` không có gây timeout.

**Sửa:**
- `USC_NUM_FRAMEBUFFERS=2` → lsc-wrapper pass `--enable-num-framebuffers=2` vào USC → buffer queue align với gralloc expectation
- `HYBRIS_LIBMINISF_DISABLE=1` → bỏ qua libminisf lookup (không có trên thiết bị)
- `HYBRIS_SKIP_WAIT_FOR_FB_DEV=1` → tránh fake SurfaceFlinger contention

---

## [HIGH] "No device yaml config found!" — deviceinfo không match codename

**File:** `etc/deviceinfo/devices/gta7litewifi.yaml` + `halium.yaml` + `default.yaml`
**Log:**
```
[info] No device yaml config found!
[từ: hfd-service, sensorfwd, repowerd, update-machine-info-from-deviceinfo]
```
**Nguyên nhân:** Deviceinfo lookup dùng runtime device name (từ `ro.product.device` hoặc `androidboot.device`) để match YAML key. Runtime name có thể là `ot8` (Samsung MT8768 platform name) hoặc `SM-T225` — không khớp key `gta7litewifi` trong YAML → config không được load → GridUnit, DPI, orientation sai.

**Sửa:** Thêm `ot8`, `samsung-gta7litewifi` vào danh sách `Names:` trong cả 3 file YAML. Sync 3 file cho nhất quán.

---

## [HIGH] NetworkManager: dhcpcd không có → assertion failed ×8

**File:** `etc/NetworkManager/conf.d/99-gta7litewifi.conf`
**Log:**
```
DHCP client 'dhcpcd' not available
(nm-device.c:4767): assertion '<dropped>' failed [×8]
```
**Nguyên nhân:** Fix trước đặt `dhcp=dhcpcd` trong NM config, nhưng `dhcpcd` không được cài trên Ubuntu Touch focal. NM fallback thất bại → assertion dropped × 8 lần → WiFi DHCP không ổn định.

**Sửa:** Xóa `dhcp=dhcpcd`. Ubuntu Touch dùng NM internal DHCP client.

---

## [HIGH] usb_moded: MTP function không có + UDC write invalid

**File:** `etc/modules-load.d/gta7litewifi.conf` + `etc/init/mount-android.conf`
**Log:**
```
functions/mtp.mtp: mkdir failed: No such file or directory
idVendor: write failure: Invalid argument
/UDC: write failure: Invalid argument
mode setting failed, try charging_only
```
**Nguyên nhân:** Module `usb_f_mtp` và `usb_f_rndis` chưa được load trước khi usb_moded start → configfs không có MTP function → mkdir fail. `idVendor` Invalid argument = gadget bị lock bởi Android side.

**Sửa:**
- Thêm `usb_f_mtp` và `usb_f_rndis` vào đầu modules-load.d (trước WMT stack)
- Bind mount `/etc/usb-moded` và `/etc/modprobe.d` từ userdata (writable) trong mount-android.conf để usb_moded ghi được config

---

## [MEDIUM] sensorfwd: HYBRIS CTL setDelay → -1 (HAL chưa ready)

**File:** `usr/lib/systemd/system/sensorfwd.service.d/wait-android.conf` (mới)
**Log:**
```
HYBRIS CTL setDelay(1=ACCELEROMETER) -> -1=Unknown error
proximitysensor instantiation failed
```
**Nguyên nhân:** sensorfwd probe sensor HAL trước khi Android LXC container khởi động xong → HAL không respond.

**Sửa:** Tạo systemd drop-in `After=lxc@android.service` + `Restart=on-failure` với `RestartSec=5s` để sensorfwd retry sau khi HAL sẵn sàng.

---

## [MEDIUM] repowerd: NoSessionForPID + power button không suspend đúng

**File:** `usr/lib/systemd/system/repowerd.service.d/wait-logind.conf` (mới)
**File:** `usr/share/repowerd/device-configs/config-default.xml`
**Log:**
```
NoSessionForPID: PID 2047 does not belong to any known session
Power key pressed. [→ USC crash thay vì suspend]
```
**Nguyên nhân:** repowerd start trước khi logind xử lý xong sessions → không track được session → power button không quản lý được đúng. `config_suspendWhenScreenOffDueToProximity=true` + proximity sensor fail = thiết bị không wake được từ suspend.

**Sửa:**
- Drop-in `After=systemd-logind.service` cho repowerd
- Set `config_suspendWhenScreenOffDueToProximity=false` (proximity sensor fail với -1)

---

## [LOW] DBus: Lomiri → USC Input calls bị rejected ×12

**File:** `etc/dbus-1/system.d/lomiri-usc-input.conf` (mới)
**Log:**
```
Rejected: lomiri setTouchpadPrimaryButton → com.lomiri.SystemCompositor.Input
[×12 method calls bị từ chối]
```
**Nguyên nhân:** DBus policy không cho phép Lomiri (uid=32011) gọi USC Input interface.

**Sửa:** Tạo DBus policy config cho phép user `phablet` gọi `com.lomiri.SystemCompositor.Input`.

---

## Files mới được tạo trong v2

| File | Lý do |
|------|-------|
| `usr/lib/systemd/system/repowerd.service.d/wait-logind.conf` | repowerd start sau logind |
| `usr/lib/systemd/system/sensorfwd.service.d/wait-android.conf` | sensorfwd retry sau LXC |
| `etc/dbus-1/system.d/lomiri-usc-input.conf` | Lomiri→USC Input policy |
