# Dotfiles & NixOS Configuration (`homepc`)

Cấu hình NixOS thuần sử dụng Flake cho workstation chạy Hyprland / Sway, chuyển đổi trực tiếp từ Fedora OSTree (`uBlue`) không cần USB boot, giữ tính chất immutable ở cả `/nix/store` và `/etc` (qua `erofs` / `composefs` overlay).

---

## 1. Cấu trúc thư mục NixOS

- `flake.nix` & `flake.lock`: Điểm vào Flake (`nixosConfigurations.homepc`, alias `workstation`), khóa phiên bản `nixpkgs` (`nixos-unstable-small`), `akquick`, và `celluloid-src`.
- `nixos/configuration.nix`: Cấu hình **OS & Hệ thống lõi**:
  - Bootloader `systemd-boot` + `zramSwap`.
  - Immutable `/etc` overlay (`system.etc.overlay.enable = true`, `mutable = true` với lớp ghi tách riêng tại `/.rw-etc/upper`) kết hợp `services.userborn.enable = true`.
  - `programs.nh` (`nh os switch` tự dùng flake mặc định, không cần gõ `sudo` hay `--flake`) và `trusted-users`.
  - Phần cứng Intel UHD 730 (`hardware.graphics` + `intel-media-driver`, `vpl-gpu-rt`), PipeWire, Bluetooth, NetworkManager + plugin **`nm-openvpn-sso`** đóng gói native (`nixos/openvpn-sso/`).
  - Tương thích FHS cho binary tải ngoài (như `~/opt/antigravity`) và script thông qua `programs.nix-ld` + `services.envfs`.
  - Tài khoản `phamnv` (`uid=1000`, `gid=1000`) kèm `services.gnome.gnome-keyring` + `machine-id` cố định để giữ nguyên mật khẩu và Chrome keyring.
- `nixos/desktop.nix`: Cấu hình **Desktop, Bộ gõ & Ứng dụng**:
  - `programs.hyprland.enable`, `programs.hyprlock.enable` (tạo sẵn PAM `/etc/pam.d/hyprlock`), `programs.sway.enable`.
  - Bộ gõ tiếng Việt `fcitx5` (`waylandFrontend = true`, `fcitx5-unikey`, `fcitx5-bamboo`).
  - Font chữ (`nerd-fonts.monaspace`, `noto-fonts`, `noto-fonts-cjk-sans`, `noto-fonts-color-emoji`).
  - `environment.systemPackages` và `systemd.user.tmpfiles.rules` (tự động duy trì toàn bộ symlink từ `~/dev/dotfiles/` sang `~/.config/`, `~/.local/bin/` và `~/.local/share/applications/` thay thế hoàn toàn `setup.sh`).
- `nixos/hardware-configuration.nix`: Cấu hình mountpoint Btrfs (`subvol=nixos`, `subvol=nix`, `subvol=home`) và EFI `/boot`.

### Lệnh sử dụng hằng ngày

```bash
# Áp dụng thay đổi cấu hình (không cần gõ sudo hay --flake)
nh os switch

# Cập nhật input trong flake.lock rồi áp dụng
nix flake update && nh os switch

# Kiểm tra những file nào bị thay đổi runtime trong /etc so với cấu hình gốc
ls -la /.rw-etc/upper
```

---

## 2. Hướng dẫn Move từ Fedora OSTree (`uBlue` / Silverblue) sang NixOS không cần USB

Áp dụng khi máy hiện tại đang chạy Fedora Atomic / OSTree trên **Btrfs** và **đã cài sẵn Nix** (hoặc cài qua Determinate Nix Installer). Toàn bộ quá trình cài đặt thực hiện trực tiếp từ terminal trên Fedora, giữ nguyên `/home` và giữ nguyên OSTree làm đường lùi cho tới khi NixOS chạy ổn định hoàn toàn.

### 2.1. Sơ đồ Btrfs trước và sau khi chuyển

Trên Btrfs pool (ví dụ `/dev/nvme0n1p3`, gốc `subvolid=5`), ta tạo thêm `subvol=nixos` và `subvol=nix` ngang hàng với `subvol=home` và `subvol=root` (OSTree cũ):

```mermaid
flowchart TD
    subgraph Before["Trước (Fedora OSTree)"]
        B_ROOT["subvol=root (OSTree /sysroot, /usr ro, /var)"]
        B_HOME["subvol=home (/var/home)"]
        B_NIX_OLD["subvol=home/nix (/nix lồng trong home)"]
        B_HOME --> B_NIX_OLD
    end

    subgraph During["Trong khi cài song song (subvolid=5)"]
        D_OLD["subvol=root (OSTree cũ - giữ làm đường lùi)"]
        D_HOME["subvol=home (Dùng chung dữ liệu người dùng)"]
        D_NIXOS["subvol=nixos (Root mới của NixOS)"]
        D_NIX["subvol=nix (Tách phẳng cho /nix/store mới)"]
    end

    subgraph After["Sau khi dọn OSTree"]
        A_NIXOS["subvol=nixos (/)"]
        A_NIX["subvol=nix (/nix)"]
        A_HOME["subvol=home (/home)"]
    end

    Before --> During --> After
```

### 2.2. Các bẫy đặc thù trên Fedora OSTree & cách né

1. **Bẫy symlink `/mnt -> var/mnt`:**
   - Trên OSTree, `/mnt` là symlink trỏ về `var/mnt`. Khi mount ổ đĩa vào `/mnt/nixos`, kernel ghi vào `/proc/self/mountinfo` đường dẫn thật `/var/mnt/nixos`, làm `nixos-generate-config --root /mnt/nixos` so lệch chuỗi và **bỏ sót toàn bộ `fileSystems`**.
   - **Cách né:** Luôn mount và truyền đường dẫn thật **`/var/mnt/nixos`** (không có symlink). Không dùng `/run/nixos` để tránh rủi ro tràn RAM `tmpfs` nếu mount nhầm.
2. **Bẫy SELinux `Enforcing` chặn `nixos-enter`:**
   - `nixos-install` chạy `nixos-enter` (chroot) ở bước cài `systemd-boot` và kích hoạt `/etc`. Chính sách SELinux của Fedora sẽ chặn tiến trình trong chroot.
   - **Cách né:** Chạy `sudo setenforce 0` trước khi chạy `nixos-install`.
3. **Bẫy `PATH` và `~/.nix-profile` cũ:**
   - Nếu dotfiles hoặc `environment.d` gán cứng `PATH` với `~/.nix-profile/bin` và `/var/home/...` của Fedora, khi boot sang NixOS sẽ che mất `/run/wrappers/bin` và `/run/current-system/sw/bin`, làm bar/launcher/hotkey không khởi chạy được.
   - **Cách né:** Đưa `/run/wrappers/bin` và `/run/current-system/sw/bin` lên đầu `PATH` (và `/run/current-system/sw/share` lên đầu `XDG_DATA_DIRS`), dùng `$HOME` hoặc `/home/<user>` thay cho `/var/home/<user>`.
4. **Giữ tài khoản, mật khẩu, Keyring và Wi-Fi:**
   - **UID/GID:** Fedora dùng `uid=1000`, `gid=1000`, còn NixOS mặc định gán `gid=100` (`users`). Phải khai báo `users.groups.<user>.gid = 1000` và `uid = 1000`.
   - **Keyring & Mật khẩu:** Giữ nguyên `/etc/machine-id` (xem bằng `cat /etc/machine-id`), bật `services.gnome.gnome-keyring.enable = true`, và trích xuất password hash từ `/etc/shadow` của Fedora sang `/var/lib/nixos/<user>-password-hash` (`chmod 0600`) kết hợp `hashedPasswordFile`.
   - **Wi-Fi / NetworkManager:** Khi dùng `system.etc.overlay`, chép các file `.nmconnection` từ `/etc/NetworkManager/system-connections/` vào `/var/mnt/nixos/.rw-etc/upper/NetworkManager/system-connections/` (`chown root:root`, `chmod 0600`).

---

### 2.3. Quy trình 3 tầng an toàn

#### Tầng 1: Test boot thử trong QEMU VM ngay trên Fedora (không đụng ổ cứng)

Kiểm tra cấu hình NixOS (`kernel`, `systemd initrd`, `/etc` overlay, user/groups) bằng cách mount trực tiếp `/nix/store` hiện tại vào QEMU qua `virtiofs`:

```bash
# Build VM test
nix build /home/phamnv/dev/dotfiles#nixosConfigurations.workstation.config.system.build.vm -o result-vm

# Chạy VM (nếu đang trên Fedora cần bọc nixGLIntel cho cửa sổ QEMU)
nixGLIntel ./result-vm/bin/run-homepc-vm
```

*(Gợi ý: Thêm block `virtualisation.vmVariant` tạm thời với `password = "1234"` và `autologinUser` để test đăng nhập nhanh trong VM).*

#### Tầng 2: Build trước & Cài vào Btrfs subvolume ngay trên Fedora

1. **Build sẵn toàn bộ system closure với quyền user thường:**
   ```bash
   nix build /home/phamnv/dev/dotfiles#nixosConfigurations.workstation.config.system.build.toplevel -o result-system
   ```

2. **Tạo subvolume & mount vào đường dẫn thật `/var/mnt/nixos` (thay UUID/thiết bị đúng với máy bạn):**
   ```bash
   sudo setenforce 0
   sudo mkdir -p /var/mnt/btrfs /var/mnt/nixos

   sudo mount -o subvolid=5 /dev/nvme0n1p3 /var/mnt/btrfs
   sudo btrfs subvolume create /var/mnt/btrfs/nixos
   sudo btrfs subvolume create /var/mnt/btrfs/nix

   sudo mount -o subvol=nixos,compress=zstd:1,noatime /dev/nvme0n1p3 /var/mnt/nixos
   sudo mkdir -p /var/mnt/nixos/{nix,home,boot}
   sudo mount -o subvol=nix,compress=zstd:1,noatime /dev/nvme0n1p3 /var/mnt/nixos/nix
   sudo mount -o subvol=home,compress=zstd:1,relatime /dev/nvme0n1p3 /var/mnt/nixos/home
   sudo mount /dev/nvme0n1p1 /var/mnt/nixos/boot
   ```

3. **Chép password hash (để login và mở khóa `login.keyring`):**
   ```bash
   sudo mkdir -p /var/mnt/nixos/var/lib/nixos
   sudo awk -F: '$1 == "phamnv" { printf "%s", $2 }' /etc/shadow | sudo tee /var/mnt/nixos/var/lib/nixos/phamnv-password-hash >/dev/null
   sudo chmod 0600 /var/mnt/nixos/var/lib/nixos/phamnv-password-hash
   ```

4. **Chạy `nixos-install` (copy gói từ `/nix/store` sang `subvol=nix` và cài `systemd-boot` lên ESP):**
   ```bash
   sudo nix shell --inputs-from "path:/home/phamnv/dev/dotfiles" nixpkgs#nixos-install-tools \
     -c nixos-install --root /var/mnt/nixos --system "$(readlink -f result-system)" --no-root-passwd
   ```
   *(Lưu ý không bọc `env PATH="$PATH"` trong `nix shell -c`, vì shell ngoài sẽ mở rộng `$PATH` trước và ghi đè đường dẫn của `nixos-install-tools`).*

5. **Chép sẵn cấu hình Wi-Fi/NetworkManager sang `/.rw-etc/upper`:**
   ```bash
   sudo mkdir -p /var/mnt/nixos/.rw-etc/upper/NetworkManager/system-connections
   sudo chmod 0700 /var/mnt/nixos/.rw-etc/upper/NetworkManager/system-connections
   sudo cp -a /etc/NetworkManager/system-connections/* /var/mnt/nixos/.rw-etc/upper/NetworkManager/system-connections/
   sudo chown root:root /var/mnt/nixos/.rw-etc/upper/NetworkManager/system-connections/*
   sudo chmod 0600 /var/mnt/nixos/.rw-etc/upper/NetworkManager/system-connections/*
   ```

#### Tầng 3: Test boot thật bằng bảo hiểm UEFI `BootNext` & Dọn OSTree sau khi ổn định

1. **Giữ Fedora làm mặc định ở `BootOrder`, chỉ đặt `BootNext` một lần sang NixOS:**
   ```bash
   # Xem mã BootXXXX của Fedora (vd: 0006) và entry mới tạo "Linux Boot Manager" (\EFI\systemd\systemd-bootx64.efi trên PARTUUID của ESP)
   efibootmgr

   # Giữ Fedora đứng đầu BootOrder, đặt BootNext sang NixOS
   sudo efibootmgr -o 0006,<NIXOS_BOOT_NUM>
   sudo efibootmgr -n <NIXOS_BOOT_NUM>
   ```
   -> Chạy `systemctl reboot`. Nếu boot NixOS gặp sự cố, chỉ cần bấm nút Reset/Power là lần kế tiếp UEFI tự quay về Fedora.

2. **Sau khi đã vào NixOS ổn định (chốt mặc định & dọn OSTree cũ):**
   ```bash
   # 1. Chốt NixOS lên đầu BootOrder
   nix shell nixpkgs#efibootmgr -c sudo efibootmgr -o <NIXOS_BOOT_NUM>,0006

   # 2. Gỡ profile Nix cũ của Fedora (và xóa symlink icon/binary sót trong ~/.local)
   rm -f ~/.nix-profile
   find ~/.local/share/icons -xtype l -delete

   # 3. Xóa subvolume OSTree cũ (subvol=root và /home/nix cũ) để thu hồi dung lượng
   sudo mkdir -p /mnt/btrfs
   sudo mount -o subvolid=5 /dev/nvme0n1p3 /mnt/btrfs
   sudo btrfs subvolume delete /mnt/btrfs/root
   sudo rm -rf /mnt/btrfs/home/nix
   sudo umount /mnt/btrfs && sudo rmdir /mnt/btrfs
   ```
