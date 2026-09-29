SUMMARY = "EGLFS KMS configuration for the CarPanel DPI display"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://eglfs-kms.json \
           file://qt-eglfs.sh"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${sysconfdir}/qt
    install -m 0644 ${WORKDIR}/eglfs-kms.json ${D}${sysconfdir}/qt/

    install -d ${D}${sysconfdir}/profile.d
    install -m 0644 ${WORKDIR}/qt-eglfs.sh ${D}${sysconfdir}/profile.d/
}
