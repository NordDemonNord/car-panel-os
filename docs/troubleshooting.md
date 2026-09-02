# Проблемы и решения / Troubleshooting

Проблемы, встреченные при развёртывании Yocto и первой сборке образа для Raspberry Pi 4.

Окружение: Ubuntu 24.04 LTS (noble), Yocto 5.0 LTS (scarthgap), Raspberry Pi 4 Model B.

---

## РУССКИЙ

### 1. Пакет `libegl1-mesa` не найден

**Симптом**
```
E: Невозможно найти пакет libegl1-mesa
```

**Причина**
Начиная с Ubuntu 24.04 пакет переименован. Официальная документация Yocto ещё указывает старое имя.

**Решение**
Использовать `libegl1` вместо `libegl1-mesa` в списке зависимостей.

---

### 2. Зависает `git clone` по протоколу `git://`

**Симптом**
Команда `git clone -b scarthgap git://git.yoctoproject.org/poky` висит без вывода и без счётчика объектов.

**Причина**
Протокол `git://` работает на порту 9418, который часто блокируется провайдерами и корпоративными файрволами.

**Решение**
Клонировать по HTTPS (порт 443):
```bash
git clone -b scarthgap https://git.yoctoproject.org/git/poky
git clone -b scarthgap https://git.yoctoproject.org/git/meta-raspberrypi
git clone -b scarthgap https://git.openembedded.org/meta-openembedded
```

---

### 3. BitBake не стартует: отсутствует локаль `en_US.UTF-8`

**Симптом**
```
ERROR: Unable to start bitbake server (None)
ERROR: Server didn't start, last 60 loglines (.../bitbake-cookerdaemon.log):
Please make sure locale 'en_US.UTF-8' is available on your system
```

**Причина**
BitBake требует локаль `en_US.UTF-8`. На системах, установленных не на английском языке, она часто не сгенерирована.

**Решение**
```bash
sudo locale-gen en_US.UTF-8
sudo update-locale LANG=en_US.UTF-8
locale -a | grep en_US    # проверка: должно вывести en_US.utf8
```
После этого перезапустить терминал и заново выполнить `source oe-init-build-env`.

---

### 4. BitBake не работает: user namespaces заблокированы AppArmor

**Симптом**
```
ERROR: User namespaces are not usable by BitBake, possibly due to AppArmor.
```

**Причина**
Начиная с Ubuntu 23.10 AppArmor по умолчанию ограничивает непривилегированные user namespaces, которые BitBake использует для изоляции задач сборки.

**Решение**
Создать профиль AppArmor. Путь к Python проверить через `python3 --version` и `readlink -f $(command -v python3)`.

```bash
sudo nano /etc/apparmor.d/bitbake
```

Содержимое (подставить актуальный путь к python3):
```
abi <abi/4.0>,
include <tunables/global>

profile bitbake /usr/bin/python3.12 flags=(unconfined) {
  userns,

  include if exists <local/bitbake>
}
```

Применить:
```bash
sudo apparmor_parser -r /etc/apparmor.d/bitbake
```

---

### 5. WARNING `do_fetch: Failed to fetch URL ...` во время сборки

**Симптом**
Десятки предупреждений вида:
```
WARNING: gcc-source-13.4.0-r0 do_fetch: Failed to fetch URL https://ftpmirror.gnu.org/..., attempting MIRRORS if available
```

**Причина**
Основные upstream-зеркала (ftpmirror.gnu.org, download.savannah.gnu.org) недоступны или медленны.

**Решение**
Ничего делать не нужно. BitBake автоматически переключается на PREMIRRORS — собственные зеркала Yocto Project. Проверять нужно итоговую строку:
```
NOTE: Tasks Summary: Attempted 3729 tasks of which 0 didn't need to be rerun and all succeeded.
```
`WARNING` — не ошибка, сборка успешна.

---

### 6. Raspberry Pi не загружается: образ скопирован пофайлово

**Симптом**
Карта отформатирована вручную, файлы из образа скопированы в разделы. При подаче питания зелёный светодиод гаснет, система не загружается.

**Причина**
Файл `.wic` — это полный образ диска **вместе с таблицей разделов**, а не архив с файлами. Его нельзя распаковывать и копировать вручную. При ручном копировании теряются `.dtb` (device tree) и папка `overlays/` — без device tree ядро не стартует.

**Решение**
Записать образ побайтово через `dd`. Форматировать и размечать карту заранее не нужно — `dd` перезапишет таблицу разделов.

```bash
lsblk                                    # определить устройство (диск целиком, не раздел!)
sudo umount /dev/sdX1 /dev/sdX2
cd ~/yocto/build/tmp/deploy/images/raspberrypi4-64/
bzcat core-image-minimal-raspberrypi4-64.rootfs.wic.bz2 \
  | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

**Проверка корректной записи:**
- раздел `boot` — около 136 МБ FAT, содержит `bcm2711-rpi-4-b.dtb` и папку `overlays/`
- раздел `root` — около 49 МБ ext4 (по размеру rootfs, а не по размеру карты)
- остаток карты — неразмеченное свободное место

---

### 7. Нет SSH-доступа к собранному образу

**Причина**
`core-image-minimal` по умолчанию не содержит SSH-сервера.

**Решение**
В `build/conf/local.conf` добавить одну строку:
```
EXTRA_IMAGE_FEATURES += "ssh-server-openssh debug-tweaks"
```

- `ssh-server-openssh` — устанавливает OpenSSH;
- `debug-tweaks` — разрешает вход root с пустым паролем (**только для разработки**, в продакшене убрать).

Использовать `+=`, а не `?=`: `?=` присваивает значение только если переменная не задана, что может перезаписать другие фичи образа.

После правки пересобрать и заново записать карту:
```bash
bitbake core-image-minimal
```

---

### 8. Raspberry Pi не видна в сети после загрузки

**Симптом**
`nmap -sn 192.168.1.0/24` не находит устройство, `ping raspberrypi4-64.local` не резолвится.

**Причины и решения**

*Ping по имени.* В `core-image-minimal` нет mDNS-демона (avahi), поэтому имена `.local` не резолвятся. Это ожидаемо и не является признаком проблемы.

*Сканирование сети.* Запускать nmap через `sudo` — тогда используются ARP-запросы вместо ICMP, и находятся хосты, не отвечающие на ping:
```bash
sudo nmap -sn 192.168.1.0/24
```
MAC-адреса Raspberry Pi начинаются с `dc:a6:32`, `e4:5f:01` или `b8:27:eb`.

*Диагностика по светодиодам без монитора.* Зелёный светодиод ACT на Pi 4 — индикатор обращений к SD-карте, а не признак «система жива». После загрузки система простаивает, обращений к карте нет, и светодиод гаснет — это **нормальное поведение**. Признак ошибки — циклически повторяющиеся серии из одинакового числа вспышек (4 вспышки — не запустился `start.elf`, 7 — не найдено ядро, 8 — проблема с SDRAM).

Гораздо надёжнее смотреть на **светодиоды Ethernet-разъёма**: если они горят, значит ядро загрузилось, драйвер сетевой карты поднялся и физический линк есть.

*Главная рекомендация.* Диагностировать загрузку вслепую — потеря времени. Подключить монитор по micro-HDMI (или USB-UART к GPIO) и увидеть полный лог загрузки.

---

### 9. Проверка работы SSH с выводом на монитор

Записать текст напрямую в системную консоль (это экран, подключённый по HDMI):
```bash
echo "SSH works!" > /dev/tty1
```

Другие способы:
```bash
wall "Hello from SSH"          # сообщение во все терминалы сразу
who                            # показать активные сессии: tty1 (монитор) и pts/0 (SSH)

# помигать светодиодом ACT
echo none > /sys/class/leds/ACT/trigger
echo 1    > /sys/class/leds/ACT/brightness
echo 0    > /sys/class/leds/ACT/brightness
echo mmc0 > /sys/class/leds/ACT/trigger    # вернуть штатное поведение
```

---
---

## ENGLISH

### 1. Package `libegl1-mesa` not found

**Symptom**
```
E: Unable to locate package libegl1-mesa
```

**Cause**
The package was renamed starting with Ubuntu 24.04. Official Yocto documentation still lists the old name.

**Fix**
Use `libegl1` instead of `libegl1-mesa` in the dependency list.

---

### 2. `git clone` hangs over the `git://` protocol

**Symptom**
`git clone -b scarthgap git://git.yoctoproject.org/poky` hangs with no output and no object counter.

**Cause**
The `git://` protocol uses port 9418, which is frequently blocked by ISPs and corporate firewalls.

**Fix**
Clone over HTTPS (port 443):
```bash
git clone -b scarthgap https://git.yoctoproject.org/git/poky
git clone -b scarthgap https://git.yoctoproject.org/git/meta-raspberrypi
git clone -b scarthgap https://git.openembedded.org/meta-openembedded
```

---

### 3. BitBake fails to start: missing `en_US.UTF-8` locale

**Symptom**
```
ERROR: Unable to start bitbake server (None)
ERROR: Server didn't start, last 60 loglines (.../bitbake-cookerdaemon.log):
Please make sure locale 'en_US.UTF-8' is available on your system
```

**Cause**
BitBake requires the `en_US.UTF-8` locale. On systems installed in a non-English language it is often not generated.

**Fix**
```bash
sudo locale-gen en_US.UTF-8
sudo update-locale LANG=en_US.UTF-8
locale -a | grep en_US    # verify: should print en_US.utf8
```
Restart the terminal afterwards and re-run `source oe-init-build-env`.

---

### 4. BitBake fails: user namespaces blocked by AppArmor

**Symptom**
```
ERROR: User namespaces are not usable by BitBake, possibly due to AppArmor.
```

**Cause**
Since Ubuntu 23.10, AppArmor restricts unprivileged user namespaces by default. BitBake uses them to isolate build tasks.

**Fix**
Create an AppArmor profile. Check the Python path with `python3 --version` and `readlink -f $(command -v python3)`.

```bash
sudo nano /etc/apparmor.d/bitbake
```

Contents (substitute the actual python3 path):
```
abi <abi/4.0>,
include <tunables/global>

profile bitbake /usr/bin/python3.12 flags=(unconfined) {
  userns,

  include if exists <local/bitbake>
}
```

Apply:
```bash
sudo apparmor_parser -r /etc/apparmor.d/bitbake
```

---

### 5. `do_fetch: Failed to fetch URL ...` warnings during the build

**Symptom**
Dozens of warnings such as:
```
WARNING: gcc-source-13.4.0-r0 do_fetch: Failed to fetch URL https://ftpmirror.gnu.org/..., attempting MIRRORS if available
```

**Cause**
Primary upstream mirrors (ftpmirror.gnu.org, download.savannah.gnu.org) are unreachable or slow.

**Fix**
No action needed. BitBake automatically falls back to PREMIRRORS — the Yocto Project's own mirrors. What matters is the final line:
```
NOTE: Tasks Summary: Attempted 3729 tasks of which 0 didn't need to be rerun and all succeeded.
```
A `WARNING` is not an error; the build succeeded.

---

### 6. Raspberry Pi won't boot: image copied file-by-file

**Symptom**
The card was formatted manually and image files were copied into the partitions. On power-up the green LED goes dark and the system does not boot.

**Cause**
A `.wic` file is a full disk image **including the partition table**, not an archive of files. It must not be unpacked and copied manually. Manual copying loses the `.dtb` (device tree) files and the `overlays/` directory — without a device tree the kernel will not start.

**Fix**
Write the image byte-for-byte with `dd`. There is no need to format or partition the card beforehand — `dd` overwrites the partition table.

```bash
lsblk                                    # identify the device (whole disk, not a partition!)
sudo umount /dev/sdX1 /dev/sdX2
cd ~/yocto/build/tmp/deploy/images/raspberrypi4-64/
bzcat core-image-minimal-raspberrypi4-64.rootfs.wic.bz2 \
  | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

**Verifying a correct write:**
- `boot` partition — roughly 136 MB FAT, contains `bcm2711-rpi-4-b.dtb` and the `overlays/` directory
- `root` partition — roughly 49 MB ext4 (sized to the rootfs, not to the card)
- the remainder of the card — unallocated free space

---

### 7. No SSH access to the built image

**Cause**
`core-image-minimal` ships without an SSH server.

**Fix**
Add a single line to `build/conf/local.conf`:
```
EXTRA_IMAGE_FEATURES += "ssh-server-openssh debug-tweaks"
```

- `ssh-server-openssh` installs OpenSSH;
- `debug-tweaks` allows root login with an empty password (**development only** — remove for production).

Use `+=` rather than `?=`: `?=` only assigns when the variable is unset, which can overwrite other image features.

Rebuild and re-flash the card afterwards:
```bash
bitbake core-image-minimal
```

---

### 8. Raspberry Pi not visible on the network after boot

**Symptom**
`nmap -sn 192.168.1.0/24` finds nothing; `ping raspberrypi4-64.local` fails to resolve.

**Causes and fixes**

*Ping by hostname.* `core-image-minimal` has no mDNS daemon (avahi), so `.local` names do not resolve. This is expected and not a sign of trouble.

*Network scanning.* Run nmap under `sudo` — it then uses ARP requests instead of ICMP and finds hosts that do not answer pings:
```bash
sudo nmap -sn 192.168.1.0/24
```
Raspberry Pi MAC addresses start with `dc:a6:32`, `e4:5f:01` or `b8:27:eb`.

*LED diagnostics without a monitor.* The green ACT LED on the Pi 4 indicates SD card activity, not "system alive". Once booted the system idles, there is no card activity, and the LED goes dark — this is **normal behaviour**. An actual error is signalled by cyclically repeating flash groups of a fixed count (4 flashes — `start.elf` did not launch, 7 — kernel not found, 8 — SDRAM failure).

The **Ethernet port LEDs** are a far more reliable signal: if they are lit, the kernel booted, the NIC driver came up, and a physical link is established.

*Main recommendation.* Diagnosing boot problems blind wastes time. Connect a monitor over micro-HDMI (or a USB-UART adapter to the GPIO header) and read the full boot log.

---

### 9. Verifying SSH with output on the monitor

Write text directly to the system console (the HDMI-attached screen):
```bash
echo "SSH works!" > /dev/tty1
```

Other options:
```bash
wall "Hello from SSH"          # broadcast to every terminal at once
who                            # list active sessions: tty1 (monitor) and pts/0 (SSH)

# blink the ACT LED
echo none > /sys/class/leds/ACT/trigger
echo 1    > /sys/class/leds/ACT/brightness
echo 0    > /sys/class/leds/ACT/brightness
echo mmc0 > /sys/class/leds/ACT/trigger    # restore default behaviour
```
