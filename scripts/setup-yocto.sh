#!/usr/bin/env bash
#
# setup-yocto.sh — развёртывание Yocto-окружения для сборки образа Raspberry Pi 4.
# Проверено на Ubuntu 24.04 LTS (noble), Yocto 5.0 LTS (scarthgap).
#
# Использование:
#   ./scripts/setup-yocto.sh [путь_к_рабочей_директории]
# По умолчанию рабочая директория — ~/yocto
#
# Скрипт НЕ запускает сборку. После него нужно:
#   cd <WORKDIR>/poky && source oe-init-build-env ../build
#   bitbake core-image-minimal

set -euo pipefail

YOCTO_BRANCH="scarthgap"
WORKDIR="${1:-$HOME/yocto}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log()  { echo -e "\n=== $* ===\n"; }
fail() { echo "ОШИБКА: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Проверки окружения
# ---------------------------------------------------------------------------
log "Проверка окружения"

[[ "$(uname -s)" == "Linux" ]] || fail "Скрипт рассчитан на Linux."
[[ $EUID -ne 0 ]] || fail "Не запускай от root — BitBake этого не допускает."

AVAIL_GB=$(df -BG --output=avail "$(dirname "$WORKDIR")" | tail -1 | tr -dc '0-9')
if (( AVAIL_GB < 100 )); then
    echo "ВНИМАНИЕ: свободно ${AVAIL_GB} ГБ. Сборке нужно 100+ ГБ."
    read -rp "Продолжить? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 1
fi

# ---------------------------------------------------------------------------
# 2. Зависимости хоста
# ---------------------------------------------------------------------------
log "Установка зависимостей хоста"

# libegl1-mesa переименован в libegl1 начиная с Ubuntu 24.04
sudo apt-get update
sudo apt-get install -y \
    gawk wget git diffstat unzip texinfo gcc build-essential chrpath \
    socat cpio python3 python3-pip python3-pexpect xz-utils debianutils \
    iputils-ping python3-git python3-jinja2 libegl1 libsdl1.2-dev \
    python3-subunit mesa-common-dev zstd liblz4-tool file locales libacl1

# ---------------------------------------------------------------------------
# 3. Локаль en_US.UTF-8 (без неё не стартует bitbake server)
# ---------------------------------------------------------------------------
log "Настройка локали en_US.UTF-8"

if ! locale -a 2>/dev/null | grep -qi "en_US.utf8"; then
    sudo locale-gen en_US.UTF-8
    sudo update-locale LANG=en_US.UTF-8
    echo "Локаль сгенерирована. Может потребоваться перелогиниться."
else
    echo "Локаль уже есть."
fi

# ---------------------------------------------------------------------------
# 4. AppArmor: user namespaces для BitBake (Ubuntu 23.10+)
# ---------------------------------------------------------------------------
log "Настройка AppArmor для BitBake"

PYTHON_BIN="$(readlink -f "$(command -v python3)")"

if [[ ! -f /etc/apparmor.d/bitbake ]]; then
    sudo tee /etc/apparmor.d/bitbake >/dev/null <<EOF
abi <abi/4.0>,
include <tunables/global>

profile bitbake ${PYTHON_BIN} flags=(unconfined) {
  userns,

  include if exists <local/bitbake>
}
EOF
    sudo apparmor_parser -r /etc/apparmor.d/bitbake
    echo "Профиль AppArmor создан для ${PYTHON_BIN}"
else
    echo "Профиль AppArmor уже существует."
fi

# ---------------------------------------------------------------------------
# 5. Клонирование слоёв
# ---------------------------------------------------------------------------
log "Клонирование слоёв (ветка ${YOCTO_BRANCH})"

# Только https: протокол git:// (порт 9418) часто блокируется провайдерами.
mkdir -p "$WORKDIR"
cd "$WORKDIR"

clone_layer() {
    local url="$1" dir="$2"
    if [[ -d "$dir" ]]; then
        echo "$dir уже существует, пропускаю."
    else
        git clone -b "$YOCTO_BRANCH" "$url" "$dir"
    fi
}

clone_layer "https://git.yoctoproject.org/git/poky"                poky
clone_layer "https://git.yoctoproject.org/git/meta-raspberrypi"    meta-raspberrypi
clone_layer "https://git.openembedded.org/meta-openembedded"       meta-openembedded

# ---------------------------------------------------------------------------
# 6. Инициализация build-окружения и конфигов
# ---------------------------------------------------------------------------
log "Инициализация build-окружения"

cd "$WORKDIR/poky"
# shellcheck disable=SC1091
source oe-init-build-env "$WORKDIR/build" >/dev/null

# local.conf берём из репозитория, bblayers.conf генерируем —
# в нём абсолютные пути, которые у каждого свои.
if [[ -f "$REPO_ROOT/configs/local.conf" ]]; then
    cp "$REPO_ROOT/configs/local.conf" "$WORKDIR/build/conf/local.conf"
    echo "local.conf скопирован из репозитория."
else
    echo "ВНИМАНИЕ: configs/local.conf не найден, оставляю сгенерированный по умолчанию."
fi

cat > "$WORKDIR/build/conf/bblayers.conf" <<EOF
# Сгенерировано setup-yocto.sh — пути зависят от машины.
POKY_BBLAYERS_CONF_VERSION = "2"

BBPATH = "\${TOPDIR}"
BBFILES ?= ""

BBLAYERS ?= " \\
  ${WORKDIR}/poky/meta \\
  ${WORKDIR}/poky/meta-poky \\
  ${WORKDIR}/poky/meta-yocto-bsp \\
  ${WORKDIR}/meta-raspberrypi \\
  ${WORKDIR}/meta-openembedded/meta-oe \\
  "
EOF
echo "bblayers.conf сгенерирован."

# ---------------------------------------------------------------------------
# Готово
# ---------------------------------------------------------------------------
log "Готово"

cat <<EOF
Окружение развёрнуто в: ${WORKDIR}

Дальнейшие шаги:

  cd ${WORKDIR}/poky
  source oe-init-build-env ../build
  bitbake core-image-minimal

Первая сборка занимает несколько часов.
Готовый образ появится в:
  ${WORKDIR}/build/tmp/deploy/images/raspberrypi4-64/core-image-minimal-raspberrypi4-64.rootfs.wic.bz2

Запись на SD-карту (ВНИМАТЕЛЬНО проверь имя устройства через lsblk!):
  sudo umount /dev/sdX1 /dev/sdX2
  bzcat core-image-minimal-raspberrypi4-64.rootfs.wic.bz2 | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
  sync
EOF
