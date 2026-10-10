import QtQuick

// ＋アイコン（描画）
Item {
    id: root
    property color color: "#9a9a9a"
    property real thickness: 1.6
    implicitWidth: 12
    implicitHeight: 12

    Rectangle {
        width: root.width
        height: root.thickness
        radius: root.thickness / 2
        color: root.color
        anchors.centerIn: parent
    }
    Rectangle {
        width: root.thickness
        height: root.height
        radius: root.thickness / 2
        color: root.color
        anchors.centerIn: parent
    }
}
