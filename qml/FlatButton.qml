import QtQuick
import QtQuick.Controls

// アプリ共通のフラットボタン（色は呼び出し側から渡す）
// ダイアログのカーソルキー選択にも使えるよう selected 状態を持つ
Button {
    id: control

    property color bgColor: "transparent"
    property color hoverColor: Qt.rgba(1, 1, 1, 0.08)
    property color textColor: "#e8e8e8"
    property color primaryColor: "#4cc2ff"
    property bool primary: false
    /// カーソルキーで選ばれているボタン
    property bool selected: false

    readonly property bool filled: primary || selected

    // フォーカスは親（ダイアログの footer 等）が持つのでボタン自身は取らない
    focusPolicy: Qt.NoFocus

    leftPadding: 16
    rightPadding: 16
    topPadding: 7
    bottomPadding: 7

    background: Rectangle {
        radius: 7
        color: control.filled
               ? (control.pressed ? Qt.darker(control.primaryColor, 1.15)
                  : (control.hovered ? Qt.lighter(control.primaryColor, 1.1) : control.primaryColor))
               : (control.pressed ? Qt.rgba(0, 0, 0, 0.20)
                  : (control.hovered ? control.hoverColor
                     : (control.selected ? Qt.rgba(control.primaryColor.r, control.primaryColor.g,
                                                   control.primaryColor.b, 0.16)
                                         : control.bgColor)))
        Behavior on color { ColorAnimation { duration: 100 } }
    }

    contentItem: Text {
        text: control.text
        color: control.filled ? "#0d1116" : control.textColor
        font: control.font
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        opacity: control.enabled ? 1.0 : 0.45
    }
}
