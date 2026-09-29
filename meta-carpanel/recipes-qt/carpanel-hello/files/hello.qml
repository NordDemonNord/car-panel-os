import QtQuick
import QtQuick.Window

Window {
    width: 1024
    height: 600
    visible: true
    color: "black"

    Text {
        anchors.centerIn: parent
        text: "CarPanel OS"
        color: "white"
        font.pixelSize: 64
    }

    Rectangle {
        width: 120
        height: 120
        x: 80
        y: 240
        color: "red"
        NumberAnimation on rotation {
            from: 0
            to: 360
            duration: 2000
            loops: Animation.Infinite
        }
    }
}
