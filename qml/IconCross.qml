import QtQuick

// 細い×アイコン（文字グリフではなく描画で出す）
Item {
    id: root
    property color color: "#9a9a9a"
    property real thickness: 1.4
    implicitWidth: 10
    implicitHeight: 10

    Rectangle {
        width: root.width
        height: root.thickness
        radius: root.thickness / 2
        color: root.color
        anchors.centerIn: parent
        rotation: 45
    }
    Rectangle {
        width: root.width
        height: root.thickness
        radius: root.thickness / 2
        color: root.color
        anchors.centerIn: parent
        rotation: -45
    }
}
