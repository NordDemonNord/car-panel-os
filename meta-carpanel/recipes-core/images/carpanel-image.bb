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
