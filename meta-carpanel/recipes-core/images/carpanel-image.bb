SUMMARY = "CarPanel OS image for the infotainment display"
LICENSE = "MIT"
require recipes-core/images/core-image-minimal.bb

IMAGE_FEATURES += "ssh-server-openssh"

# Diagnostics and development tools
IMAGE_INSTALL += " \
    systemd-analyze \
    i2c-tools \
    nano \
    "

# Qt 6 runtime with the eglfs_kms backend
IMAGE_INSTALL += " \
    qtbase \
    qtbase-plugins \
    qtdeclarative \
    qtdeclarative-qmlplugins \
    qtsvg \
    ttf-dejavu-sans \
    kmscube \
    eglfs-config \
    carpanel-hello \
    qt-instrument-cluster \
    "

# CP2102, STM32 link
IMAGE_INSTALL += " \
    kernel-module-cp210x \
    "
# SLCAN link to the STM32: kernel driver, slcand/candump, Qt CAN API + socketcan plugin
IMAGE_INSTALL += " \
    kernel-module-slcan \
    can-utils \
    qtserialbus \
    qtserialbus-plugins \
    can-utils-slcan \
    kernel-module-can \
    kernel-module-can-raw \
    "
