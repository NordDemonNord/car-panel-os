SUMMARY = "EGLFS KMS configuration for the CarPanel DPI display"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://eglfs-kms.json \
           file://qt-eglfs.env \
           file://qt-eglfs.sh"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${sysconfdir}/qt
    install -m 0644 ${WORKDIR}/eglfs-kms.json ${D}${sysconfdir}/qt/

    # Single source of truth: read by systemd units (EnvironmentFile=)
    # and by login shells (via profile.d).
    install -d ${D}${sysconfdir}/default
    install -m 0644 ${WORKDIR}/qt-eglfs.env ${D}${sysconfdir}/default/qt-eglfs

    install -d ${D}${sysconfdir}/profile.d
    install -m 0644 ${WORKDIR}/qt-eglfs.sh ${D}${sysconfdir}/profile.d/
}
