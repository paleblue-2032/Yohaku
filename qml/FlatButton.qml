import QtQuick
import QtQuick.Controls

// アプリ共通のフラットボタン（色は呼び出し側から渡す）
Button {
    id: control

    property color bgColor: "transparent"
    property color hoverColor: Qt.rgba(1, 1, 1, 0.08)
    property color textColor: "#e8e8e8"
    property color primaryColor: "#4cc2ff"
    property bool primary: false

    leftPadding: 16
    rightPadding: 16
    topPadding: 7
    bottomPadding: 7

    background: Rectangle {
        radius: 7
        color: control.primary
               ? (control.pressed ? Qt.darker(control.primaryColor, 1.15)
                  : (control.hovered ? Qt.lighter(control.primaryColor, 1.1) : control.primaryColor))
               : (control.pressed ? Qt.rgba(0, 0, 0, 0.20)
                  : (control.hovered ? control.hoverColor : control.bgColor))
        Behavior on color { ColorAnimation { duration: 100 } }
    }

    contentItem: Text {
        text: control.text
        color: control.primary ? "#0d1116" : control.textColor
        font: control.font
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        opacity: control.enabled ? 1.0 : 0.45
    }
}
