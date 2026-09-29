SUMMARY = "Minimal QML scene to verify Qt on the DPI panel"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://hello.qml"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${datadir}/carpanel
    install -m 0644 ${WORKDIR}/hello.qml ${D}${datadir}/carpanel/
}

FILES:${PN} += "${datadir}/carpanel"

RDEPENDS:${PN} = "qtdeclarative-tools"
