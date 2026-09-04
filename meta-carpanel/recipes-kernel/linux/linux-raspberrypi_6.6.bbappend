do_configure:append() {
    for s in BACKLIGHT_CLASS_DEVICE DRM_PANEL_SIMPLE; do
        sed -i "/^CONFIG_${s}=/d;/^# CONFIG_${s} is not set/d" ${B}/.config
        echo "CONFIG_${s}=y" >> ${B}/.config
    done
    yes '' | oe_runmake -C ${S} O=${B} oldconfig
}
