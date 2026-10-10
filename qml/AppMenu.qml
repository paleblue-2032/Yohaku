import QtQuick
import QtQuick.Controls
import QtQuick.Effects

// アプリ内メニュー（角丸 + 影 + ホバー + カーソルキー操作）
// items: [{ label, shortcut?, checked?, separator?, action: function }]
Popup {
    id: menu

    property var items: []
    property color surfaceColor: "#262626"
    property color borderColor: "#333333"
    property color textColor: "#e8e8e8"
    property color mutedColor: "#9a9a9a"
    property color accentColor: "#4cc2ff"
    property color hoverColor: "#ffffff14"
    property string uiFontFamily: ""

    property int currentIndex: -1

    width: 272
    height: column.implicitHeight + 16
    padding: 8
    focus: true
    modal: false
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    function move(dir) {
        const n = items.length;
        if (n === 0)
            return;
        let i = menu.currentIndex;
        for (let k = 0; k < n; ++k) {
            i = (i + dir + n) % n;
            if (!items[i].separator) {
                menu.currentIndex = i;
                return;
            }
        }
    }

    function activate() {
        if (menu.currentIndex < 0 || menu.currentIndex >= items.length)
            return;
        const it = items[menu.currentIndex];
        if (!it || it.separator)
            return;
        menu.close();
        if (it.action)
            it.action();
    }

    // 閉じたら元の入力先にフォーカスを戻す
    property var returnFocusTo: null

    onOpened: {
        currentIndex = -1;
        column.forceActiveFocus();
    }

    onClosed: if (returnFocusTo)
                  returnFocusTo.forceActiveFocus()

    background: Rectangle {
        color: menu.surfaceColor
        radius: 10
        border.width: 1
        border.color: menu.borderColor
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#99000000"
            shadowBlur: 1.0
            shadowVerticalOffset: 8
            shadowHorizontalOffset: 0
        }
    }

    contentItem: Column {
        id: column
        focus: true
        spacing: 2

        Keys.onUpPressed: menu.move(-1)
        Keys.onDownPressed: menu.move(1)
        Keys.onReturnPressed: menu.activate()
        Keys.onEnterPressed: menu.activate()
        Keys.onEscapePressed: menu.close()

        Repeater {
            model: menu.items
            delegate: Item {
                width: column.width
                height: modelData.separator ? 9 : 30

                Rectangle {
                    visible: modelData.separator === true
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 1
                    color: menu.borderColor
                }

                Rectangle {
                    visible: !(modelData.separator === true)
                    anchors.fill: parent
                    radius: 6
                    color: index === menu.currentIndex ? menu.hoverColor : "transparent"

                    Rectangle {
                        visible: modelData.checked === true
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6
                        height: 6
                        radius: 3
                        color: menu.accentColor
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                        anchors.right: shortcutText.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label ? modelData.label : ""
                        color: modelData.checked === true ? menu.accentColor : menu.textColor
                        font.family: menu.uiFontFamily
                        font.pixelSize: 14
                        elide: Text.ElideRight
                    }

                    Text {
                        id: shortcutText
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.shortcut ? modelData.shortcut : ""
                        color: menu.mutedColor
                        font.family: menu.uiFontFamily
                        font.pixelSize: 12
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !(modelData.separator === true)
                    hoverEnabled: true
                    onEntered: menu.currentIndex = index
                    onClicked: {
                        const a = modelData.action;
                        menu.close();
                        if (a)
                            a();
                    }
                }
            }
        }
    }
}
