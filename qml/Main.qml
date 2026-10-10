import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

ApplicationWindow {
    id: root
    width: 940
    height: 700
    minimumWidth: 480
    minimumHeight: 320
    visible: true
    color: theme.bg
    font.family: App.uiFont
    font.pixelSize: Settings.fontSize

    property int activeIndex: tabBar.currentIndex
    property int cursorLine: 1
    property int cursorColumn: 1
    property bool panelOpen: false
    property int jumpLine: 0
    property int jumpToken: 0

    // i18n: rev を読むことで言語変更時にバインディングが再評価される
    function tr(key) {
        let r = I18n.rev;
        return I18n.t(key);
    }

    function requestJump(line) {
        root.jumpLine = line;
        root.jumpToken++;
    }

    function titleOf(i) {
        const p = Docs.pathAt(i);
        return p === "" ? root.tr("untitled") : Docs.titleAt(i);
    }

    // ---- 色トークン ----
    QtObject {
        id: theme
        readonly property bool dark: Settings.dark
        readonly property color accent: Settings.accent

        readonly property color bg: dark ? "#1b1b1b" : "#ffffff"
        readonly property color panel: dark ? "#202020" : "#f3f3f3"
        readonly property color surface: dark ? "#262626" : "#ffffff"
        readonly property color hover: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
        readonly property color border: dark ? "#333333" : "#e2e2e2"
        readonly property color text: dark ? "#e8e8e8" : "#1a1a1a"
        readonly property color muted: dark ? "#9a9a9a" : "#6a6a6a"
    }

    palette.window: theme.panel
    palette.windowText: theme.text
    palette.base: theme.bg
    palette.alternateBase: theme.surface
    palette.text: theme.text
    palette.button: theme.surface
    palette.buttonText: theme.text
    palette.highlight: theme.accent
    palette.highlightedText: "#101010"

    title: (Docs.count > 0 ? titleOf(root.activeIndex) : "") + " — shiori"

    // ---- ファイル操作 ----
    function newTab() {
        Docs.addUntitled();
        tabBar.currentIndex = Docs.count - 1;
    }

    function closeCurrent() {
        root.pendingClose = root.activeIndex;
        if (Docs.isModifiedAt(root.activeIndex))
            closeConfirm.open();
        else
            doClose();
    }

    function doClose() {
        if (Docs.count <= 1) {
            Docs.setLineMarks(Docs.keyAt(0), Bookmarks.lineMarks(Docs.keyAt(0)));
            return;
        }
        Bookmarks.setLastPosition(Docs.keyAt(root.pendingClose), root.cursorLine);
        Docs.closeAt(root.pendingClose);
        if (tabBar.currentIndex >= Docs.count)
            tabBar.currentIndex = Docs.count - 1;
        closeConfirm.close();
    }

    function saveCurrent() {
        const i = root.activeIndex;
        if (i < 0)
            return;
        if (!Docs.saveAt(i))
            openSaveAs(i);
    }

    function openSaveAs(i) {
        saveDialog.currentIndex = i;
        saveDialog.currentFile = Docs.pathAt(i) !== "" ? Docs.pathAt(i) : titleOf(i) + ".txt";
        saveDialog.open();
    }

    function toggleLineBookmark() {
        const i = root.activeIndex;
        if (i < 0)
            return;
        const key = Docs.keyAt(i);
        let marks = Bookmarks.lineMarks(key);
        const line = root.cursorLine;
        const pos = marks.indexOf(line);
        if (pos >= 0)
            marks.splice(pos, 1);
        else
            marks.push(line);
        Bookmarks.setLineMarks(key, marks);
    }

    function toggleFileBookmark() {
        const i = root.activeIndex;
        if (i < 0)
            return;
        const key = Docs.keyAt(i);
        Bookmarks.toggleFile(key, titleOf(i), Docs.pathAt(i));
    }

    property int pendingClose: 0

    // ---- 表示モード / 検索 ----
    property bool preview: App.startInPreview
    property bool searchOpen: App.initialQuery !== ""
    property string query: App.initialQuery
    property int searchIndex: 0
    property var matches: []
    property var activeEditor: null
    property var activeFlick: null

    function openSearch() {
        root.searchOpen = true;
        Qt.callLater(function () { searchField.forceActiveFocus(); searchField.selectAll(); });
    }

    function closeSearch() {
        root.searchOpen = false;
        root.query = "";
        root.matches = [];
        if (root.activeEditor)
            root.activeEditor.forceActiveFocus();
    }

    function recomputeSearch() {
        const a = root.activeEditor;
        if (!a || root.query === "") {
            root.matches = [];
            root.searchIndex = 0;
            return;
        }
        const t = a.text;
        const q = root.query;
        const res = [];
        let i = t.indexOf(q);
        while (i >= 0 && res.length < 2000) {
            res.push(i);
            i = t.indexOf(q, i + q.length);
        }
        root.matches = res;
        if (root.searchIndex >= res.length)
            root.searchIndex = 0;
    }

    function searchStep(dir) {
        if (root.matches.length === 0)
            return;
        root.searchIndex = (root.searchIndex + dir + root.matches.length) % root.matches.length;
        root.jumpToCurrentMatch();
    }

    function jumpToCurrentMatch() {
        const a = root.activeEditor;
        const f = root.activeFlick;
        if (!a || !f || root.matches.length === 0)
            return;
        const pos = root.matches[root.searchIndex];
        a.cursorPosition = pos;
        const r = a.positionToRectangle(pos);
        f.contentY = Math.max(0, r.y - f.height * 0.35);
    }

    // ---- メニュー（ウィンドウ内ポップアップ） ----
    Menu {
        id: fileMenu
            title: root.tr("file")
            palette.window: theme.surface
            palette.windowText: theme.text
            palette.text: theme.text
            palette.highlight: theme.accent
            palette.highlightedText: "#101010"
            popupType: Popup.Item
            Action { text: root.tr("new"); shortcut: StandardKey.New; onTriggered: root.newTab() }
            Action { text: root.tr("open"); shortcut: StandardKey.Open; onTriggered: openDialog.open() }
            MenuSeparator {}
            Action { text: root.tr("save"); shortcut: StandardKey.Save; onTriggered: root.saveCurrent() }
            Action { text: root.tr("saveAs"); onTriggered: root.openSaveAs(root.activeIndex) }
            MenuSeparator {}
            Action { text: root.tr("closeTab"); shortcut: StandardKey.Close; onTriggered: root.closeCurrent() }
            Action { text: root.tr("quit"); shortcut: StandardKey.Quit; onTriggered: root.tryQuit() }
        }
        Menu {
            id: viewMenu
            title: root.tr("view")
            palette.window: theme.surface
            palette.windowText: theme.text
            palette.text: theme.text
            palette.highlight: theme.accent
            palette.highlightedText: "#101010"
            popupType: Popup.Item
            MenuItem {
                text: root.tr("wordWrap"); checkable: true; checked: Settings.wrap
                onTriggered: Settings.wrap = checked
            }
            MenuItem {
                text: root.tr("lineNumbers"); checkable: true; checked: Settings.lineNumbers
                onTriggered: Settings.lineNumbers = checked
            }
            Action {
                text: root.tr("preview"); shortcut: "Ctrl+P"
                checkable: true; checked: root.preview
                onTriggered: root.preview = checked
            }
            MenuSeparator {}
            Action {
                text: root.tr("find"); shortcut: "Ctrl+F"
                onTriggered: root.openSearch()
            }
        }
        Menu {
            id: bookmarksMenu
            title: root.tr("bookmarks")
            palette.window: theme.surface
            palette.windowText: theme.text
            palette.text: theme.text
            palette.highlight: theme.accent
            palette.highlightedText: "#101010"
            popupType: Popup.Item
            Action { text: root.tr("bookmarkLine"); shortcut: "Ctrl+B"; onTriggered: root.toggleLineBookmark() }
            Action {
                text: Bookmarks.isFileBookmarked(Docs.count > 0 ? Docs.keyAt(root.activeIndex) : "")
                      ? root.tr("bookmarkFileRemove") : root.tr("bookmarkFileAdd")
                shortcut: "Ctrl+Shift+B"
                onTriggered: root.toggleFileBookmark()
            }
            MenuSeparator {}
            MenuItem {
                text: root.tr("bookmarkPanel"); checkable: true; checked: root.panelOpen
                onTriggered: root.panelOpen = checked
            }
        }
        Menu {
            id: settingsMenu
            title: root.tr("settings")
            palette.window: theme.surface
            palette.windowText: theme.text
            palette.text: theme.text
            palette.highlight: theme.accent
            palette.highlightedText: "#101010"
            popupType: Popup.Item
            Menu {
                title: root.tr("theme")
            palette.window: theme.surface
            palette.windowText: theme.text
            palette.text: theme.text
            palette.highlight: theme.accent
            palette.highlightedText: "#101010"
            popupType: Popup.Item
                MenuItem { text: root.tr("dark"); checkable: true; checked: Settings.dark; onTriggered: Settings.dark = true }
                MenuItem { text: root.tr("light"); checkable: true; checked: !Settings.dark; onTriggered: Settings.dark = false }
            }
            Menu {
                title: root.tr("accent")
            palette.window: theme.surface
            palette.windowText: theme.text
            palette.text: theme.text
            palette.highlight: theme.accent
            palette.highlightedText: "#101010"
            popupType: Popup.Item
                MenuItem { text: "Blue"; onTriggered: Settings.accent = "#4cc2ff" }
                MenuItem { text: "Amber"; onTriggered: Settings.accent = "#e6b450" }
                MenuItem { text: "Green"; onTriggered: Settings.accent = "#5fbf7f" }
                MenuItem { text: "Pink"; onTriggered: Settings.accent = "#e07a9a" }
                MenuItem { text: "Purple"; onTriggered: Settings.accent = "#a98bf0" }
            }
            Menu {
                title: root.tr("language")
            palette.window: theme.surface
            palette.windowText: theme.text
            palette.text: theme.text
            palette.highlight: theme.accent
            palette.highlightedText: "#101010"
            popupType: Popup.Item
                MenuItem { text: "English"; checkable: true; checked: Settings.language === "en"; onTriggered: Settings.language = "en" }
                MenuItem { text: "日本語"; checkable: true; checked: Settings.language === "ja"; onTriggered: Settings.language = "ja" }
            }
            MenuSeparator {}
            MenuItem { text: root.tr("fontSize") + " +"; onTriggered: Settings.fontSize = Settings.fontSize + 1 }
            MenuItem { text: root.tr("fontSize") + " −"; onTriggered: Settings.fontSize = Settings.fontSize - 1 }
        }

    // ---- 上部バー（メニュー行 + タブ行） ----
    header: ColumnLayout {
        spacing: 0

        // メニュー行
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 30
            color: theme.panel

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 4
                anchors.rightMargin: 8
                spacing: 2

                Button {
                    id: fileBtn
                    text: root.tr("file")
                    leftPadding: 8
                    rightPadding: 8
                    onClicked: fileMenu.popup(fileBtn, 0, fileBtn.height)
                    background: Rectangle {
                        radius: 6
                        color: (fileBtn.hovered || fileMenu.visible) ? theme.hover : "transparent"
                    }
                    contentItem: Text {
                        text: fileBtn.text
                        color: theme.text
                        font.family: root.font.family
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                Button {
                    id: viewBtn
                    text: root.tr("view")
                    leftPadding: 8
                    rightPadding: 8
                    onClicked: viewMenu.popup(viewBtn, 0, viewBtn.height)
                    background: Rectangle {
                        radius: 6
                        color: (viewBtn.hovered || viewMenu.visible) ? theme.hover : "transparent"
                    }
                    contentItem: Text {
                        text: viewBtn.text
                        color: theme.text
                        font.family: root.font.family
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                Button {
                    id: bookmarksBtn
                    text: root.tr("bookmarks")
                    leftPadding: 8
                    rightPadding: 8
                    onClicked: bookmarksMenu.popup(bookmarksBtn, 0, bookmarksBtn.height)
                    background: Rectangle {
                        radius: 6
                        color: (bookmarksBtn.hovered || bookmarksMenu.visible) ? theme.hover : "transparent"
                    }
                    contentItem: Text {
                        text: bookmarksBtn.text
                        color: theme.text
                        font.family: root.font.family
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                Button {
                    id: settingsBtn
                    text: root.tr("settings")
                    leftPadding: 8
                    rightPadding: 8
                    onClicked: settingsMenu.popup(settingsBtn, 0, settingsBtn.height)
                    background: Rectangle {
                        radius: 6
                        color: (settingsBtn.hovered || settingsMenu.visible) ? theme.hover : "transparent"
                    }
                    contentItem: Text {
                        text: settingsBtn.text
                        color: theme.text
                        font.family: root.font.family
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                Item { Layout.fillWidth: true }
            }
        }

        // タブ行
        Rectangle {
        id: tabStrip
        Layout.fillWidth: true
        implicitHeight: 40
        color: theme.panel

        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.border }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 8
            spacing: 6

            TabBar {
                id: tabBar
                Layout.fillWidth: true
                Layout.fillHeight: true
                padding: 0
                background: Item {}

                Repeater {
                    model: Docs
                    TabButton {
                        id: tabBtn
                        width: Math.min(230, implicitWidth + 40)

                        background: Item {
                            Rectangle {
                                anchors.fill: parent
                                anchors.topMargin: 5
                                anchors.bottomMargin: 5
                                radius: 7
                                color: tabBtn.checked ? theme.surface : (tabBtn.hovered ? theme.hover : "transparent")
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                width: tabBtn.checked ? Math.max(0, parent.width - 28) : 0
                                height: 2
                                radius: 1
                                color: theme.accent
                                Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            }
                        }

                        contentItem: Text {
                            text: (model.modified ? "● " : "") + root.titleOf(index)
                            color: tabBtn.checked ? theme.text : theme.muted
                            font.family: root.font.family
                            font.pixelSize: 14
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            rightPadding: tabBtn.checked ? 16 : 0
                        }

                        Button {
                            id: closeBtn
                            visible: tabBtn.checked
                            width: 20
                            height: 20
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: {
                                root.pendingClose = index;
                                if (Docs.isModifiedAt(index))
                                    closeConfirm.open();
                                else
                                    root.doClose();
                            }
                            background: Rectangle {
                                radius: 5
                                color: closeBtn.hovered ? theme.hover : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            contentItem: Item { IconCross { anchors.centerIn: parent; color: theme.muted } }
                        }
                    }
                }
            }

            Button {
                id: newTabBtn
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                Layout.alignment: Qt.AlignVCenter
                onClicked: root.newTab()
                background: Rectangle {
                    radius: 7
                    color: newTabBtn.hovered ? theme.hover : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
                contentItem: Item { IconPlus { anchors.centerIn: parent; color: theme.muted } }
            }
        }
    }

        // 検索バー
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: root.searchOpen ? 36 : 0
            visible: root.searchOpen
            color: theme.panel

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                spacing: 6

                TextField {
                    id: searchField
                    Layout.preferredWidth: 260
                    placeholderText: root.tr("findHint")
                    text: root.query
                    color: theme.text
                    placeholderTextColor: theme.muted
                    font.family: root.font.family
                    font.pixelSize: 14
                    background: Rectangle {
                        radius: 6
                        color: theme.bg
                        border.color: theme.border
                    }
                    onTextChanged: {
                        root.query = text;
                        root.searchIndex = 0;
                        root.recomputeSearch();
                    }
                    Keys.onReturnPressed: root.searchStep(1)
                    Keys.onEscapePressed: root.closeSearch()
                }
                Text {
                    text: root.matches.length > 0
                          ? (root.searchIndex + 1) + "/" + root.matches.length
                          : "0/0"
                    color: theme.muted
                    font.family: root.font.family
                    font.pixelSize: 13
                }
                Button {
                    text: root.tr("prev")
                    onClicked: root.searchStep(-1)
                }
                Button {
                    text: root.tr("next")
                    onClicked: root.searchStep(1)
                }
                Button {
                    text: root.tr("close")
                    onClicked: root.closeSearch()
                }
                Item { Layout.fillWidth: true }
            }
        }
    }

    // ---- エディタ + 栞パネル ----
    RowLayout {
        anchors.fill: parent
        spacing: 0

        StackLayout {
            id: stack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex

        Repeater {
            model: Docs

            Flickable {
                id: flick
                clip: true
                contentWidth: content.width
                contentHeight: content.height

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ScrollBar.horizontal: ScrollBar {
                    policy: Settings.wrap ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded
                }

                Item {
                    id: content
                    width: Math.max(flick.width, area.contentWidth + gutter.width + 40)
                    height: Math.max(root.preview ? previewText.implicitHeight + 48
                                                  : area.contentHeight + 32,
                                     flick.height)

                    // Markdown プレビュー
                    Text {
                        id: previewText
                        visible: root.preview
                        x: 24
                        y: 16
                        width: Math.max(0, flick.width - 48)
                        text: area.text
                        textFormat: Text.MarkdownText
                        wrapMode: Text.Wrap
                        color: theme.text
                        font.family: root.font.family
                        font.pixelSize: Settings.fontSize
                        onLinkActivated: (link) => Qt.openUrlExternally(link)
                    }

                    Item {
                        id: gutter
                        width: Settings.lineNumbers ? 48 : 0
                        height: content.height
                        visible: Settings.lineNumbers && !root.preview

                        Repeater {
                            model: area.lineYs.length
                            delegate: Item {
                                x: 0
                                y: area.lineYs[index]
                                width: gutter.width
                                height: Math.max(1, area.lineHeights[index])

                                Text {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: index + 1
                                    color: theme.muted
                                    opacity: 0.55
                                    font.family: root.font.family
                                    font.pixelSize: Settings.fontSize - 3
                                }
                                Rectangle {
                                    visible: area.marks.indexOf(index + 1) >= 0
                                    x: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 3
                                    height: 14
                                    radius: 1.5
                                    color: theme.accent
                                }
                            }
                        }
                    }

                    TextArea {
                        id: area
                        visible: !root.preview
                        x: gutter.width
                        width: Math.max(0, flick.width - gutter.width)
                        height: content.height

                        property var lineStarts: [0]
                        property var lineYs: [0]
                        property var lineHeights: [0]
                        property var marks: []

                        function recomputeLines() {
                            var starts = [0];
                            var t = text;
                            for (var i = 0; i < t.length; i++) {
                                if (t.charAt(i) === "\n")
                                    starts.push(i + 1);
                            }
                            lineStarts = starts;
                            Qt.callLater(measureYs);
                        }

                        function measureYs() {
                            var ys = [];
                            var hs = [];
                            for (var j = 0; j < lineStarts.length; j++) {
                                const r = positionToRectangle(lineStarts[j]);
                                ys.push(r.y);
                                hs.push(r.height);
                            }
                            lineYs = ys;
                            lineHeights = hs;
                        }

                        function jumpToLine(line) {
                            if (line < 1 || lineStarts.length === 0)
                                return;
                            const i = Math.min(line - 1, lineStarts.length - 1);
                            const pos = lineStarts[i];
                            cursorPosition = pos;
                            const yy = positionToRectangle(pos).y + topPadding;
                            flick.contentY = Math.max(0, yy - flick.height * 0.35);
                        }

                        onContentHeightChanged: Qt.callLater(measureYs)
                        onWidthChanged: Qt.callLater(measureYs)

                        Component.onCompleted: {
                            text = model.text;
                            recomputeLines();
                            marks = Bookmarks.lineMarks(Docs.keyAt(index));
                            if (index === tabBar.currentIndex) {
                                root.activeEditor = area;
                                root.activeFlick = flick;
                                root.recomputeSearch();
                            }
                            const line = Bookmarks.lastPosition(Docs.keyAt(index));
                            if (line > 0)
                                Qt.callLater(function () { jumpToLine(line); });
                        }

                        onTextChanged: {
                            if (Docs.textAt(index) !== text)
                                Docs.setTextAt(index, text);
                            recomputeLines();
                        }

                        Connections {
                            target: root
                            function onJumpTokenChanged() {
                                if (index === root.activeIndex)
                                    jumpToLine(root.jumpLine);
                            }
                        }

                        Connections {
                            target: Bookmarks
                            function onChanged() {
                                marks = Bookmarks.lineMarks(Docs.keyAt(index));
                            }
                        }

                        wrapMode: Settings.wrap ? TextArea.Wrap : TextArea.NoWrap
                        selectByMouse: true
                        persistentSelection: true
                        color: theme.text
                        placeholderText: root.tr("placeholder")
                        placeholderTextColor: theme.muted
                        selectionColor: theme.accent
                        selectedTextColor: theme.dark ? "#101010" : "#ffffff"
                        font.family: root.font.family
                        font.pixelSize: Settings.fontSize
                        topPadding: 16
                        bottomPadding: 16
                        leftPadding: 16
                        rightPadding: 16

                        background: Rectangle { color: theme.bg }

                        onCursorPositionChanged: {
                            if (!activeFocus)
                                return;
                            const t = text.substring(0, cursorPosition);
                            const line = t.split("\n").length;
                            const col = t.length - t.lastIndexOf("\n");
                            root.cursorLine = line;
                            root.cursorColumn = col;
                            Bookmarks.setLastPosition(Docs.keyAt(index), line);
                        }

                        onActiveFocusChanged: {
                            if (activeFocus) {
                                tabBar.currentIndex = index;
                                root.activeEditor = area;
                                root.activeFlick = flick;
                                root.recomputeSearch();
                            }
                        }

                        Connections {
                            target: tabBar
                            function onCurrentIndexChanged() {
                                if (index === tabBar.currentIndex) {
                                    root.activeEditor = area;
                                    root.activeFlick = flick;
                                    root.recomputeSearch();
                                }
                            }
                        }
                    }

                    // 検索ハイライト（現在のマッチを文字の上に薄く重ねる）
                    Repeater {
                        model: (index === tabBar.currentIndex && !root.preview
                                && root.matches.length > 0) ? 1 : 0
                        delegate: Rectangle {
                            property int mpos: root.matches[root.searchIndex]
                            property int mlen: root.query.length
                            // area.lineYs を読むことで、レイアウト確定後に再評価させる
                            x: (area.lineYs.length, gutter.width + area.positionToRectangle(mpos).x)
                            y: (area.lineYs.length, area.positionToRectangle(mpos).y)
                            width: (area.lineYs.length, Math.max(2,
                                            area.positionToRectangle(Math.min(mpos + mlen, area.text.length)).x
                                            - area.positionToRectangle(mpos).x))
                            height: (area.lineYs.length, area.positionToRectangle(mpos).height)
                            radius: 2
                            color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.40)
                        }
                    }
                }
            }
        }
    }

        // ---- 栞パネル ----
        Rectangle {
            id: panel
            visible: root.panelOpen
            color: theme.panel
            Layout.preferredWidth: 250
            Layout.fillHeight: true

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: theme.border
            }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Text {
                text: root.tr("thisFileBookmarks"); color: theme.muted
                font.family: root.font.family; font.pixelSize: 12; font.bold: true
            }
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 240)
                model: {
                    Bookmarks.rev;
                    return Bookmarks.lineMarks(Docs.count > 0 ? Docs.keyAt(root.activeIndex) : "");
                }
                delegate: ItemDelegate {
                    width: ListView.view.width
                    text: String(modelData)
                    onClicked: root.requestJump(modelData)
                    contentItem: Text {
                        text: parent.text; color: theme.text; elide: Text.ElideRight
                        font.family: root.font.family; font.pixelSize: 13
                    }
                    background: Rectangle { color: parent.hovered ? theme.hover : "transparent" }
                }
            }

            Text {
                text: root.tr("fileBookmarks"); color: theme.muted
                font.family: root.font.family; font.pixelSize: 12; font.bold: true
            }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: {
                    Bookmarks.rev;
                    return Bookmarks.files;
                }
                delegate: ItemDelegate {
                    width: ListView.view.width
                    text: modelData.title
                    onClicked: {
                        if (modelData.path !== "")
                            Docs.openPath(modelData.path);
                    }
                    contentItem: Text {
                        text: parent.text; color: theme.text; elide: Text.ElideRight
                        font.family: root.font.family; font.pixelSize: 13
                    }
                    background: Rectangle { color: parent.hovered ? theme.hover : "transparent" }
                }
            }
        }
    }
    }

    // ---- ステータスバー ----
    footer: Rectangle {
        id: statusBar
        implicitHeight: 26
        color: theme.panel

        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: theme.border }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            Text {
                text: (Docs.count > 0 ? root.titleOf(root.activeIndex) : "")
                      + "    " + root.tr("line") + " " + root.cursorLine
                      + ", " + root.tr("col") + " " + root.cursorColumn
                color: theme.muted
                font.family: root.font.family
                font.pixelSize: 12
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                text: Settings.wrap ? root.tr("wrap") : root.tr("noWrap")
                color: theme.muted
                font.family: root.font.family
                font.pixelSize: 12
            }
        }
    }

    // ---- ショートカット（メニュー外のもの） ----
    Shortcut { sequence: "Ctrl+J"; onActivated: root.panelOpen = !root.panelOpen }
    Shortcut {
        sequences: ["Ctrl+=", "Ctrl+Plus", "Ctrl++"]
        onActivated: Settings.fontSize = Settings.fontSize + 1
    }
    Shortcut {
        sequences: ["Ctrl+-", "Ctrl+Minus"]
        onActivated: Settings.fontSize = Settings.fontSize - 1
    }
    Shortcut { sequence: "Ctrl+0"; onActivated: Settings.fontSize = 15 }
    Shortcut { sequence: "Ctrl+F"; onActivated: root.openSearch() }
    Shortcut { sequence: "Ctrl+P"; onActivated: root.preview = !root.preview }
    Shortcut { sequence: "Escape"; enabled: root.searchOpen; onActivated: root.closeSearch() }

    // ---- ダイアログ ----
    FileDialog {
        id: openDialog
        title: root.tr("open")
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            for (const u of selectedFiles)
                Docs.openPath(App.pathOf(u));
        }
    }

    FileDialog {
        id: saveDialog
        property int currentIndex: 0
        title: root.tr("saveAs")
        fileMode: FileDialog.SaveFile
        onAccepted: Docs.saveAsAt(saveDialog.currentIndex, selectedFile)
    }

    Dialog {
        id: closeConfirm
        anchors.centerIn: parent
        modal: true
        popupType: Popup.Item
        title: root.tr("unsavedTitle")
        standardButtons: Dialog.NoButton
        Text {
            text: root.tr("unsavedBody").replace("%1", root.titleOf(root.pendingClose))
            color: theme.text; font.family: root.font.family
        }
        footer: RowLayout {
            spacing: 8
            Item { Layout.fillWidth: true }
            Button { text: root.tr("save"); onClicked: { closeConfirm.close(); root.saveCurrent(); root.doClose(); } }
            Button { text: root.tr("dontSave"); onClicked: { closeConfirm.close(); root.doClose(); } }
            Button { text: root.tr("cancel"); onClicked: closeConfirm.close() }
        }
    }

    Dialog {
        id: quitConfirm
        anchors.centerIn: parent
        modal: true
        popupType: Popup.Item
        title: root.tr("quitTitle")
        standardButtons: Dialog.NoButton
        Text { text: root.tr("quitBody"); color: theme.text; font.family: root.font.family }
        footer: RowLayout {
            spacing: 8
            Item { Layout.fillWidth: true }
            Button { text: root.tr("saveAndQuit"); onClicked: { quitConfirm.close(); Docs.saveAll(); root.quitting = true; Qt.quit(); } }
            Button { text: root.tr("quitNoSave"); onClicked: { quitConfirm.close(); root.quitting = true; Qt.quit(); } }
            Button { text: root.tr("cancel"); onClicked: quitConfirm.close() }
        }
    }

    function tryQuit() {
        if (Docs.anyModified())
            quitConfirm.open();
        else
            Qt.quit();
    }

    onClosing: function (close) {
        if (!root.quitting && Docs.anyModified()) {
            close.accepted = false;
            root.tryQuit();
        }
    }

    property bool quitting: false
}
