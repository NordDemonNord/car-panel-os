# Car Dashboard

Двухэкранная автомобильная приборная панель: bare-metal приборка на STM32H743IIT6 и мультимедийная система на Raspberry Pi 4 под собственной сборкой Linux (Yocto).

Учебный проект. Приоритет — освоение промышленных подходов embedded-разработки, а не скорость получения результата.

---

## РУССКИЙ

### Архитектура

Система состоит из двух вычислительных узлов, каждый со своим 10.1" дисплеем — как два экрана в приборной панели автомобиля.

```
   [ПК: симулятор CAN]
            │  UART (виртуальный COM-порт)
                     ▼
   ┌──────────────────────┐         ┌──────────────────────┐
   │  STM32H743IIT6       │  UART   │  Raspberry Pi 4      │
   │  bare-metal          │────────▶│  Yocto Linux         │
   │                      │         │  Qt                  │
   │  приборная панель    │         │  мультимедиа         │
   └──────────┬───────────┘         └──────────┬───────────┘
              │ LTDC (RGB24)                   │ RGB LCD HAT
                        ▼                                                        ▼
      ┌───────────────┐                ┌───────────────┐
      │ EP1103J-55-DCT│                │ EP1103J-55-DCT│
      │ 10.1" 1024×600│                │ 10.1" 1024×600│
      └───────────────┘                └───────────────┘
```

**STM32H743IIT6 (bare-metal)** — выводит приборную панель: скорость, обороты, индикаторы. Принимает данные по CAN, выступает в роли CPU системы и передаёт управляющие пакеты на Raspberry Pi по UART.

**Raspberry Pi 4 (Yocto Linux + Qt)** — мультимедийная система. Обрабатывает тяжёлые задачи: интерфейс, медиа. Получает управляющие пакеты от STM32.

**Симуляция CAN** — на этапе разработки CAN-пакеты эмулируются с ПК и передаются в STM32 через виртуальный COM-порт.

### Аппаратное обеспечение

| Компонент | Модель | Примечание |
|---|---|---|
| MCU | STM32H743IIT6 | bare-metal, вывод через LTDC |
| SBC | Raspberry Pi 4 Model B | Yocto Linux |
| Дисплеи | EP1103J-55-DCT ×2 | 10.1", 1024×600, RGB24, ёмкостный тач GT9271 |
| Адаптер дисплея | RGB LCD HAT | подключение дисплея к Raspberry Pi |

Ключевые параметры дисплея: интерфейс RGB 24 бит (50 pin), DCLK ~51.2 МГц (типовое), тач GT9271 по I²C (6 pin), подсветка 18–20 В / 140 мА — требует отдельного повышающего драйвера.

### Программный стек

- **Yocto Project 5.0 LTS (scarthgap)** — сборка собственного дистрибутива Linux для Raspberry Pi
- **Qt** — интерфейс мультимедийной системы
- **Хост сборки** — Ubuntu 24.04 LTS

Выбор Yocto вместо урезанной Ubuntu — осознанный: именно на Yocto построены реальные automotive-платформы (COVESA/Automotive Grade Linux). Это даёт опыт работы с BitBake, слоями, рецептами и сборкой rootfs с нуля.

### Структура репозитория

```
configs/     конфигурация сборки Yocto (local.conf, bblayers.conf)
docs/        документация, решённые проблемы
scripts/     скрипты развёртывания окружения
```

Слои Yocto (poky, meta-raspberrypi, meta-openembedded) и артефакты сборки в репозиторий не входят — они разворачиваются скриптом.

### Быстрый старт

```bash
git clone <repo-url>
cd car-dashboard
./scripts/setup-yocto.sh          # установит зависимости и склонирует слои

cd ~/yocto/poky
source oe-init-build-env ../build
bitbake core-image-minimal        # первая сборка: несколько часов
```

Запись образа на SD-карту (проверить имя устройства через `lsblk`):

```bash
cd ~/yocto/build/tmp/deploy/images/raspberrypi4-64/
sudo umount /dev/sdX1 /dev/sdX2
bzcat core-image-minimal-raspberrypi4-64.rootfs.wic.bz2 \
  | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Подключение по SSH (Raspberry Pi должна быть подключена по Ethernet):

```bash
sudo nmap -sn 192.168.1.0/24      # найти адрес
ssh root@<ip>                      # пароль не требуется (debug-tweaks)
```

Проблемы, встреченные при развёртывании, и их решения — в [docs/troubleshooting.md](docs/troubleshooting.md).

### Статус

- [x] Развёртывание окружения Yocto (scarthgap) под Raspberry Pi 4
- [x] Сборка `core-image-minimal`, загрузка на реальном железе
- [x] SSH-доступ к образу
- [ ] Подключение слоя Qt, сборка образа с графическим стеком
- [ ] Собственный layer и image recipe проекта
- [ ] Вывод на дисплей через RGB LCD HAT
- [ ] Протокол обмена STM32 ↔ Raspberry Pi по UART
- [ ] Прошивка STM32: LTDC, вывод приборной панели
- [ ] Приём CAN на STM32, симулятор CAN-пакетов на ПК

---
---

## ENGLISH

### Architecture

The system consists of two compute nodes, each driving its own 10.1" display — like the two screens in a car's dashboard.

```
   [PC: CAN simulator]
            │  UART (virtual COM port)
                     ▼
   ┌──────────────────────┐         ┌──────────────────────┐
   │  STM32H743IIT6       │  UART   │  Raspberry Pi 4      │
   │  bare-metal          │────────▶│  Yocto Linux         │
   │                      │         │  Qt                  │
   │  instrument cluster  │         │  infotainment        │
   └──────────┬───────────┘         └──────────┬───────────┘
              │ LTDC (RGB24)                   │ RGB LCD HAT
                        ▼                                                        ▼
      ┌───────────────┐                ┌───────────────┐
      │ EP1103J-55-DCT│                │ EP1103J-55-DCT│
      │ 10.1" 1024×600│                │ 10.1" 1024×600│
      └───────────────┘                └───────────────┘
```

**STM32H743IIT6 (bare-metal)** — drives the instrument cluster: speed, RPM, indicator lights. Receives data over CAN, acts as the system CPU and forwards control packets to the Raspberry Pi over UART.

**Raspberry Pi 4 (Yocto Linux + Qt)** — the infotainment system. Handles the heavy work: UI and media. Receives control packets from the STM32.

**CAN simulation** — during development CAN packets are emulated on a PC and fed to the STM32 through a virtual COM port.

### Hardware

| Component | Model | Notes |
|---|---|---|
| MCU | STM32H743IIT6 | bare-metal, display driven via LTDC |
| SBC | Raspberry Pi 4 Model B | Yocto Linux |
| Displays | EP1103J-55-DCT ×2 | 10.1", 1024×600, RGB24, GT9271 capacitive touch |
| Display adapter | RGB LCD HAT | connects the panel to the Raspberry Pi |

Key display parameters: 24-bit RGB interface (50 pin), DCLK ~51.2 MHz (typical), GT9271 touch over I²C (6 pin), backlight 18–20 V / 140 mA — requires a dedicated boost driver.

### Software stack

- **Yocto Project 5.0 LTS (scarthgap)** — building a custom Linux distribution for the Raspberry Pi
- **Qt** — infotainment user interface
- **Build host** — Ubuntu 24.04 LTS

Yocto was chosen over a stripped-down Ubuntu deliberately: real automotive platforms (COVESA / Automotive Grade Linux) are built on Yocto. It provides hands-on experience with BitBake, layers, recipes and building a rootfs from scratch.

### Repository layout

```
configs/     Yocto build configuration (local.conf, bblayers.conf)
docs/        documentation, solved problems
scripts/     environment setup scripts
```

Yocto layers (poky, meta-raspberrypi, meta-openembedded) and build artefacts are not tracked — they are provisioned by the setup script.

### Quick start

```bash
git clone <repo-url>
cd car-dashboard
./scripts/setup-yocto.sh          # installs dependencies and clones the layers

cd ~/yocto/poky
source oe-init-build-env ../build
bitbake core-image-minimal        # first build takes several hours
```

Flashing the image to an SD card (verify the device name with `lsblk`):

```bash
cd ~/yocto/build/tmp/deploy/images/raspberrypi4-64/
sudo umount /dev/sdX1 /dev/sdX2
bzcat core-image-minimal-raspberrypi4-64.rootfs.wic.bz2 \
  | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Connecting over SSH (the Raspberry Pi must be on Ethernet):

```bash
sudo nmap -sn 192.168.1.0/24      # locate the address
ssh root@<ip>                      # no password required (debug-tweaks)
```

Problems encountered during setup and their solutions are documented in [docs/troubleshooting.md](docs/troubleshooting.md).

### Status

- [x] Yocto (scarthgap) environment set up for Raspberry Pi 4
- [x] `core-image-minimal` built and booted on real hardware
- [x] SSH access to the image
- [ ] Qt layer integrated, image built with a graphics stack
- [ ] Project-specific layer and image recipe
- [ ] Display output through the RGB LCD HAT
- [ ] STM32 ↔ Raspberry Pi UART protocol
- [ ] STM32 firmware: LTDC, instrument cluster rendering
- [ ] CAN reception on the STM32, CAN packet simulator on the PC
