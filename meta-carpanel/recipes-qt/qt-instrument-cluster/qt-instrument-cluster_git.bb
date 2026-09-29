SUMMARY = "Qt Quick instrument cluster UI"
HOMEPAGE = "https://github.com/NordDemonNord/qt-instrument-cluster"

# Application code is MIT, bundled fonts are OFL-1.1.
LICENSE = "MIT & OFL-1.1"
LIC_FILES_CHKSUM = " \
    file://LICENSE;md5=0dda670a8bf32eee35b95f63ad1e8839 \
    file://assets/fonts/OFL-1.1.txt;md5=158d0399b51b0a87f2d79198b724d843 \
    "

# Pinned to an exact commit: the image always gets a known version.
SRC_URI = "git://github.com/NordDemonNord/qt-instrument-cluster.git;protocol=https;branch=main"
SRCREV = "04ca55b1e982633e3ac894f6d150f692e07f0f79"
PV = "0.1+git"
S = "${WORKDIR}/git"

# Cross-compiles a Qt 6 CMake project against the target sysroot.
inherit qt6-cmake

# Build time: libraries to link against, plus host tools
# (qmlcachegen, qmltyperegistrar) from qtdeclarative-native.
DEPENDS = " \
    qtbase \
    qtdeclarative \
    qtdeclarative-native \
    qtsvg \
    qt5compat \
    "

# Run time: loaded dynamically, so the linker cannot see them.
#   qtdeclarative-qmlplugins - QtQuick
#   qt5compat-qmlplugins     - Qt5Compat.GraphicalEffects
#   qtsvg-plugins            - SVG image format for Image { source: "*.svg" }
RDEPENDS:${PN} = " \
    qtdeclarative-qmlplugins \
    qt5compat-qmlplugins \
    qtsvg-plugins \
    "
