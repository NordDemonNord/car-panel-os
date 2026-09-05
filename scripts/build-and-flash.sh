#!/usr/bin/env bash
#
# build-and-flash.sh — сборка образа Yocto и запись на SD-карту.
#
# Использование:
#   ./scripts/build-and-flash.sh                    # собрать и спросить, куда писать
#   ./scripts/build-and-flash.sh --device /dev/sda  # собрать и записать на указанное устройство
#   ./scripts/build-and-flash.sh --build-only       # только собрать
#   ./scripts/build-and-flash.sh --flash-only       # только записать (использовать готовый образ)
#
# Переменные окружения:
#   YOCTO_DIR   рабочая директория Yocto (по умолчанию ~/yocto)
#   IMAGE       имя образа (по умолчанию carpanel-image)
#   MACHINE     целевая машина (по умолчанию raspberrypi4-64)

set -euo pipefail


set_paths() {
    WIC="$DEPLOY_DIR/${IMAGE}-${MACHINE}.rootfs.wic.bz2"
    BMAP="$DEPLOY_DIR/${IMAGE}-${MACHINE}.rootfs.wic.bmap"
}


YOCTO_DIR="${YOCTO_DIR:-$HOME/yocto}"
IMAGE="${IMAGE:-carpanel-image}"
MACHINE="${MACHINE:-raspberrypi4-64}"

DEPLOY_DIR="$YOCTO_DIR/build/tmp/deploy/images/$MACHINE"
set_paths

DEVICE=""
DO_BUILD=1
DO_FLASH=1

# --- цвета для читаемости вывода -------------------------------------------
if [[ -t 1 ]]; then
    R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[1m'; N=$'\e[0m'
else
    R=""; G=""; Y=""; B=""; N=""
fi


log()  { echo -e "\n${B}=== $* ===${N}\n"; }
warn() { echo -e "${Y}$*${N}"; }
fail() { echo -e "${R}ОШИБКА: $*${N}" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Разбор аргументов
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --device|-d) DEVICE="$2"; shift 2 ;;
        --build-only) DO_FLASH=0; shift ;;
        --flash-only) DO_BUILD=0; shift ;;
        --image) IMAGE="$2"; shift 2 ;;
        -h|--help)
            sed -n '3,17p' "$0" | sed 's/^# \?//'
            exit 0 ;;
        *) fail "Неизвестный аргумент: $1 (см. --help)" ;;
    esac
done

# пути зависят от IMAGE, пересчитываем после разбора аргументов
set_paths


[[ $EUID -ne 0 ]] || fail "Не запускай от root — BitBake этого не допускает."

# ---------------------------------------------------------------------------
# Сборка
# ---------------------------------------------------------------------------
if (( DO_BUILD )); then
    log "Сборка ${IMAGE} для ${MACHINE}"

    [[ -d "$YOCTO_DIR/poky" ]] || fail "Не найден $YOCTO_DIR/poky. Запусти сначала setup-yocto.sh"

    cd "$YOCTO_DIR/poky"
    # oe-init-build-env обращается к необъявленным переменным (BBSERVER и др.),
    # поэтому на время его выполнения отключаем set -u
    set +u
    # shellcheck disable=SC1091
    source oe-init-build-env "$YOCTO_DIR/build" >/dev/null
    set -u

    START=$(date +%s)
    bitbake "$IMAGE"
    ELAPSED=$(( $(date +%s) - START ))

    echo -e "\n${G}Сборка завершена за $((ELAPSED/60)) мин $((ELAPSED%60)) сек${N}"
fi

if (( ! DO_FLASH )); then
    log "Готово (сборка без записи)"
    echo "Образ: $WIC"
    exit 0
fi

# ---------------------------------------------------------------------------
# Проверка наличия образа
# ---------------------------------------------------------------------------
[[ -f "$WIC" ]] || fail "Образ не найден: $WIC"
[[ -f "$BMAP" ]] || fail "Не найден bmap: $BMAP"

IMG_SIZE=$(du -h "$WIC" | cut -f1)
IMG_DATE=$(date -r "$WIC" '+%Y-%m-%d %H:%M:%S')

# ---------------------------------------------------------------------------
# Выбор устройства
# ---------------------------------------------------------------------------
log "Выбор устройства для записи"

if [[ -z "$DEVICE" ]]; then
    echo "Съёмные устройства:"
    echo
    # RM=1 — removable; так системный диск в список не попадёт
    lsblk -dno NAME,SIZE,RM,MODEL | awk '$3==1 {printf "  /dev/%-8s %-8s %s\n", $1, $2, substr($0, index($0,$4))}'
    echo
    lsblk -dno NAME,RM | awk '$2==1' | grep -q . \
        || fail "Съёмных устройств не найдено. Вставь карту или укажи --device вручную."

    read -rp "Устройство (например /dev/sda): " DEVICE
fi

[[ -b "$DEVICE" ]] || fail "$DEVICE не является блочным устройством."

# защита от записи в раздел вместо диска
[[ "$DEVICE" =~ [0-9]$ ]] && fail "Указан раздел ($DEVICE). Нужен диск целиком, например /dev/sda"

IS_REMOVABLE=$(lsblk -dno RM "$DEVICE")
DEV_SIZE=$(lsblk -dno SIZE "$DEVICE")
DEV_MODEL=$(lsblk -dno MODEL "$DEVICE" | xargs)

if [[ "$IS_REMOVABLE" != "1" ]]; then
    warn "ВНИМАНИЕ: $DEVICE не помечено как съёмное. Это может быть системный диск!"
fi

# ---------------------------------------------------------------------------
# Подтверждение
# ---------------------------------------------------------------------------
cat <<EOF

  Образ:      $(basename "$WIC")
              ${IMG_SIZE}, собран ${IMG_DATE}

  Устройство: ${DEVICE}
              ${DEV_SIZE}  ${DEV_MODEL}

EOF

lsblk "$DEVICE"
echo

warn "Все данные на ${DEVICE} будут уничтожены."
read -rp "Для подтверждения введи имя устройства ($DEVICE): " CONFIRM
[[ "$CONFIRM" == "$DEVICE" ]] || fail "Не подтверждено, запись отменена."

# ---------------------------------------------------------------------------
# Запись
# ---------------------------------------------------------------------------
log "Отмонтирование разделов"

for part in "${DEVICE}"?*; do
    [[ -b "$part" ]] || continue
    if mount | grep -q "^$part "; then
        sudo umount "$part" && echo "отмонтирован $part"
    fi
done

log "Запись образа"

sudo bmaptool copy --bmap "$BMAP" "$WIC" "$DEVICE"

log "Готово"

echo "Карта записана. Вставь её в Raspberry Pi и подай питание."
echo
echo "Поиск платы в сети после загрузки:"
echo "  sudo nmap -sn 192.168.1.0/24     # MAC начинается с dc:a6:32 / e4:5f:01"
echo "  ssh root@<ip>"
