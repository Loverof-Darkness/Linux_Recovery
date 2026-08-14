# Maintainer: Loverof-Darkness <loverof-darkness@github>
pkgname=devil-recovery
pkgver=1.0.0
pkgrel=1
pkgdesc="DEVIL — Emergency Verification & Intelligent Linux Recovery. A comprehensive Linux boot recovery utility."
arch=('any')
url="https://github.com/Loverof-Darkness/Linux_Recovery"
license=('GPL2')
install=devil-recovery.install
depends=('bash>=5' 'coreutils' 'grep' 'sed' 'gawk' 'findutils' 'util-linux')
optdepends=(
  'efibootmgr: EFI boot entry management'
  'grub: GRUB bootloader repair'
  'os-prober: Multi-boot OS detection'
  'btrfs-progs: Btrfs subvolume support'
  'cryptsetup: LUKS encrypted volume detection'
  'lvm2: LVM volume support'
  'chafa: Terminal image rendering'
  'kitty: Kitty graphics protocol support'
)
source=("${pkgname}-${pkgver}.tar.gz::https://github.com/Loverof-Darkness/Linux_Recovery/archive/refs/heads/main.tar.gz")
sha256sums=('SKIP')

package() {
  cd "$srcdir/Linux_Recovery-main"

  # Install to /opt/devil
  install -dm755 "$pkgdir/opt/devil"
  cp -a core modules ui themes config docs scripts tests assets \
        devil devil_recovery Devil_Recovery run.sh \
        README.md LICENSE CHANGELOG.md CONTRIBUTING.md \
        install.sh uninstall.sh \
        "$pkgdir/opt/devil/"

  # Set permissions
  find "$pkgdir/opt/devil" -type d -exec chmod 0755 {} +
  find "$pkgdir/opt/devil" -type f \( -name '*.sh' -o -name 'devil' -o -name 'Devil_Recovery' -o -name 'devil_recovery' \) \
      -exec chmod 0755 {} +

  # System-wide launchers
  install -dm755 "$pkgdir/usr/local/bin"

  # devil_recovery — the main command
  ln -sf /opt/devil/devil_recovery "$pkgdir/usr/local/bin/devil_recovery"

  # devil — direct launcher
  cat > "$pkgdir/usr/local/bin/devil" << 'EOF'
#!/usr/bin/env bash
exec /opt/devil/run.sh "$@"
EOF
  chmod 0755 "$pkgdir/usr/local/bin/devil"

  # Devil_Recovery — backward compat
  ln -sf /opt/devil/Devil_Recovery "$pkgdir/usr/local/bin/Devil_Recovery"

  # Desktop entry
  install -Dm644 config/devil.desktop "$pkgdir/usr/share/applications/devil.desktop"

  # Icon
  if [[ -f assets/devil.png ]]; then
    install -Dm644 assets/devil.png "$pkgdir/usr/share/pixmaps/devil.png"
  fi

  # Auto-bootstrap profile (so `devil_recovery` auto-installs if pkg removed)
  install -Dm644 config/devil-recovery-bootstrap.sh "$pkgdir/etc/profile.d/devil-recovery-bootstrap.sh"
  if [[ -d "$pkgdir/etc/fish" ]] || true; then
    install -Dm644 config/devil-recovery-bootstrap.fish "$pkgdir/etc/fish/conf.d/devil-recovery-bootstrap.fish"
  fi
}
