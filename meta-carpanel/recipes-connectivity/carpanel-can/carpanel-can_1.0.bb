SUMMARY = "Bring up can0 over SLCAN (STM32 via CP2102) on boot"

# No own license file: point to the common MIT text shipped with poky.
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# No source code: the recipe only installs one systemd unit from files/.
SRC_URI = "file://carpanel-can.service"
S = "${WORKDIR}"

inherit systemd
SYSTEMD_SERVICE:${PN} = "carpanel-can.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/carpanel-can.service ${D}${systemd_system_unitdir}/
}

# Run time: slcand binary and kernel modules for SLCAN + SocketCAN.
RDEPENDS:${PN} = " \
    can-utils-slcan \
    kernel-module-slcan \
    kernel-module-can \
    kernel-module-can-raw \
    kernel-module-cp210x \
    "
