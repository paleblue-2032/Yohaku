import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Effects

ApplicationWindow {
    id: root
    width: 940
    height: 700
    minimumWidth: 480
    minimumHeight: 320
    visible: true
    color: "transparent"
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

    // ボタンの下にメニューを開く
    function showMenu(menu, btn) {
        menu.parent = btn;
        menu.x = 0;
        menu.y = btn.height;
        menu.open();
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

        // 透過の度合い（niri には blur が無いので、強くすると壁紙が透けて読みづらくなる）
        readonly property real alpha: Settings.windowOpacity
        readonly property color bgBase: dark ? "#1b1b1b" : "#ffffff"
        readonly property color panelBase: dark ? "#202020" : "#f3f3f3"
        readonly property color surfaceBase: dark ? "#262626" : "#ffffff"
        // 外周（メニュー行/タブ行/ステータスバー/余白）。ウィンドウ下地もこの濃度
        readonly property color bg: Qt.rgba(bgBase.r, bgBase.g, bgBase.b, alpha)
        // 入力欄は外周より少しだけ濃くする（透過はするが読みやすく）
        readonly property real editorAlpha: Math.min(1.0, alpha + 0.05)
        // 下地(bg)の上に重ねる分のアルファ。合成後が editorAlpha になる値
        readonly property real editorOverlay: alpha >= 0.999 ? 1.0
                                              : (editorAlpha - alpha) / (1.0 - alpha)
        readonly property color editorBg: Qt.rgba(bgBase.r, bgBase.g, bgBase.b, editorOverlay)
        readonly property color panel: Qt.rgba(panelBase.r, panelBase.g, panelBase.b, alpha)
        // ポップアップ・ダイアログは少し濃いめにして読みやすくする
        readonly property color surface: Qt.rgba(surfaceBase.r, surfaceBase.g, surfaceBase.b,
                                                 Math.min(1.0, alpha + 0.06))
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

    title: (Docs.count > 0 ? titleOf(root.activeIndex) : "") + " — Yohaku"

    // 起動直後やウィンドウがアクティブになったら編集エリアへフォーカスを移す。
    // （クリックしなくても、そのまま入力・カーソル移動できるようにする）
    onActiveChanged: if (active) root.focusEditor()
    Component.onCompleted: Qt.callLater(root.focusEditor)

    function focusEditor() {
        if (root.searchOpen) {
            searchField.forceActiveFocus();
            return;
        }
        if (root.activeEditor)
            root.activeEditor.forceActiveFocus();
    }

    // ---- ファイル操作 ----
    function newTab() {
        Docs.addUntitled();
        tabBar.currentIndex = Docs.count - 1;
    }

    function nextTab() {
        if (Docs.count <= 1)
            return;
        tabBar.currentIndex = (tabBar.currentIndex + 1) % Docs.count;
    }

    function prevTab() {
        if (Docs.count <= 1)
            return;
        tabBar.currentIndex = (tabBar.currentIndex - 1 + Docs.count) % Docs.count;
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
    property var openMenu: null

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

    // ---- メニュー項目（i18n に追従） ----
    readonly property var fileItems: [
        { label: root.tr("new"), shortcut: "Ctrl+T", action: function () { root.newTab(); } },
        { label: root.tr("open"), shortcut: "Ctrl+O", action: function () { openDialog.open(); } },
        { separator: true },
        { label: root.tr("save"), shortcut: "Ctrl+S", action: function () { root.saveCurrent(); } },
        { label: root.tr("saveAs"), shortcut: "Ctrl+Shift+S", action: function () { root.openSaveAs(root.activeIndex); } },
        { separator: true },
        { label: root.tr("closeTab"), shortcut: "Ctrl+W", action: function () { root.closeCurrent(); } },
        { label: root.tr("quit"), shortcut: "Ctrl+Q", action: function () { root.tryQuit(); } }
    ]

    readonly property var viewItems: [
        { label: root.tr("wordWrap"), checked: Settings.wrap, action: function () { Settings.wrap = !Settings.wrap; } },
        { label: root.tr("lineNumbers"), checked: Settings.lineNumbers, action: function () { Settings.lineNumbers = !Settings.lineNumbers; } },
        { label: root.tr("preview"), shortcut: "Ctrl+P", checked: root.preview, action: function () { root.preview = !root.preview; } },
        { separator: true },
        { label: root.tr("find"), shortcut: "Ctrl+F", action: function () { root.openSearch(); } }
    ]

    readonly property var bookmarkItems: [
        { label: root.tr("bookmarkLine"), shortcut: "Ctrl+B", action: function () { root.toggleLineBookmark(); } },
        { label: Bookmarks.isFileBookmarked(Docs.count > 0 ? Docs.keyAt(root.activeIndex) : "")
                 ? root.tr("bookmarkFileRemove") : root.tr("bookmarkFileAdd"),
          shortcut: "Ctrl+Shift+B", action: function () { root.toggleFileBookmark(); } },
        { separator: true },
        { label: root.tr("bookmarkPanel"), shortcut: "Ctrl+J", checked: root.panelOpen,
          action: function () { root.panelOpen = !root.panelOpen; } }
    ]

    readonly property var settingsItems: [
        { label: root.tr("dark"), checked: Settings.dark, action: function () { Settings.dark = true; } },
        { label: root.tr("light"), checked: !Settings.dark, action: function () { Settings.dark = false; } },
        { separator: true },
        { label: root.tr("accent") + ": Blue", checked: Settings.accent === "#4cc2ff", action: function () { Settings.accent = "#4cc2ff"; } },
        { label: root.tr("accent") + ": Amber", checked: Settings.accent === "#e6b450", action: function () { Settings.accent = "#e6b450"; } },
        { label: root.tr("accent") + ": Green", checked: Settings.accent === "#5fbf7f", action: function () { Settings.accent = "#5fbf7f"; } },
        { label: root.tr("accent") + ": Pink", checked: Settings.accent === "#e07a9a", action: function () { Settings.accent = "#e07a9a"; } },
        { label: root.tr("accent") + ": Purple", checked: Settings.accent === "#a98bf0", action: function () { Settings.accent = "#a98bf0"; } },
        { separator: true },
        { label: root.tr("transparency") + ": " + root.tr("opacityNone"),
          checked: Settings.windowOpacity >= 0.999, action: function () { Settings.windowOpacity = 1.0; } },
        { label: root.tr("transparency") + ": " + root.tr("opacityLight"),
          checked: Math.abs(Settings.windowOpacity - 0.9) < 0.015, action: function () { Settings.windowOpacity = 0.9; } },
        { label: root.tr("transparency") + ": " + root.tr("opacityMedium"),
          checked: Math.abs(Settings.windowOpacity - 0.8) < 0.015, action: function () { Settings.windowOpacity = 0.8; } },
        { label: root.tr("transparency") + ": " + root.tr("opacityStrong"),
          checked: Math.abs(Settings.windowOpacity - 0.7) < 0.015, action: function () { Settings.windowOpacity = 0.7; } },
        { separator: true },
        { label: root.tr("fontSize") + " +", shortcut: "Ctrl+Shift+Up", action: function () { Settings.fontSize = Settings.fontSize + 1; } },
        { label: root.tr("fontSize") + " −", shortcut: "Ctrl+Shift+Down", action: function () { Settings.fontSize = Settings.fontSize - 1; } },
        { separator: true },
        { label: "English", checked: Settings.language === "en", action: function () { Settings.language = "en"; } },
        { label: "日本語", checked: Settings.language === "ja", action: function () { Settings.language = "ja"; } }
    ]

    AppMenu {
        id: fileMenu
        items: root.fileItems
        surfaceColor: theme.surface
        borderColor: theme.border
        textColor: theme.text
        mutedColor: theme.muted
        accentColor: theme.accent
        hoverColor: theme.hover
        uiFontFamily: App.uiFont
        returnFocusTo: root.activeEditor
        openMenuHolder: root
    }

    AppMenu {
        id: viewMenu
        items: root.viewItems
        surfaceColor: theme.surface
        borderColor: theme.border
        textColor: theme.text
        mutedColor: theme.muted
        accentColor: theme.accent
        hoverColor: theme.hover
        uiFontFamily: App.uiFont
        returnFocusTo: root.activeEditor
        openMenuHolder: root
    }

    AppMenu {
        id: bookmarksMenu
        items: root.bookmarkItems
        surfaceColor: theme.surface
        borderColor: theme.border
        textColor: theme.text
        mutedColor: theme.muted
        accentColor: theme.accent
        hoverColor: theme.hover
        uiFontFamily: App.uiFont
        returnFocusTo: root.activeEditor
        openMenuHolder: root
    }

    AppMenu {
        id: settingsMenu
        items: root.settingsItems
        surfaceColor: theme.surface
        borderColor: theme.border
        textColor: theme.text
        mutedColor: theme.muted
        accentColor: theme.accent
        hoverColor: theme.hover
        uiFontFamily: App.uiFont
        returnFocusTo: root.activeEditor
        openMenuHolder: root
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
                    onClicked: root.showMenu(fileMenu, fileBtn)
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
                    onClicked: root.showMenu(viewMenu, viewBtn)
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
                    onClicked: root.showMenu(bookmarksMenu, bookmarksBtn)
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
                    onClicked: root.showMenu(settingsMenu, settingsBtn)
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
                // タブを切り替えたら編集エリアにフォーカスを戻す
                onCurrentIndexChanged: Qt.callLater(root.focusEditor)
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
                            visible: tabBtn.checked || tabBtn.hovered
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
                }
                Text {
                    text: root.matches.length > 0
                          ? (root.searchIndex + 1) + "/" + root.matches.length
                          : "0/0"
                    color: theme.muted
                    font.family: root.font.family
                    font.pixelSize: 13
                }
                FlatButton {
                    text: root.tr("prev")
                    textColor: theme.text
                    hoverColor: theme.hover
                    onClicked: root.searchStep(-1)
                }
                FlatButton {
                    text: root.tr("next")
                    textColor: theme.text
                    hoverColor: theme.hover
                    onClicked: root.searchStep(1)
                }
                FlatButton {
                    text: root.tr("close")
                    textColor: theme.text
                    hoverColor: theme.hover
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

                // スクロール・リサイズで可視行の範囲を更新する
                onContentYChanged: area.updateVisible()
                onHeightChanged: area.updateVisible()

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ScrollBar.horizontal: ScrollBar {
                    policy: Settings.wrap ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded
                }

                Item {
                    id: content
                    width: Math.max(flick.width, area.contentWidth + gutter.width + 40)

                    // 余白側の下地（入力欄より少しだけ透過）
                    Rectangle {
                        anchors.fill: parent
                        color: theme.bg
                    }

                    height: Math.max(root.preview ? previewText.contentHeight + 40
                                                  : area.contentHeight + 32,
                                     flick.height)

                    // Markdown プレビュー（GitHub 風に整形して表示）
                    TextEdit {
                        id: previewText
                        visible: root.preview
                        x: 20
                        y: 16
                        width: Math.max(0, flick.width - 40)
                        readOnly: true
                        selectByMouse: true
                        textFormat: TextEdit.RichText
                        wrapMode: TextEdit.Wrap
                        color: theme.text
                        font.family: App.uiFont
                        font.pixelSize: Settings.fontSize
                        onLinkActivated: (link) => Qt.openUrlExternally(link)

                        function refresh() {
                            App.renderMarkdown(previewText, root.preview ? area.text : "");
                        }

                        onVisibleChanged: if (visible) refresh()

                        Component.onCompleted: if (visible) refresh()

                        // 本文の変更・テーマ変更に追従（少し待ってから）
                        Timer {
                            id: previewDebounce
                            interval: 80
                            repeat: false
                            onTriggered: previewText.refresh()
                        }

                        Connections {
                            target: Settings
                            function onDarkChanged() { previewDebounce.restart(); }
                            function onAccentChanged() { previewDebounce.restart(); }
                            function onFontSizeChanged() { previewDebounce.restart(); }
                        }
                    }

                    Item {
                        id: gutter
                        width: Settings.lineNumbers ? 48 : 0
                        height: content.height
                        visible: Settings.lineNumbers && !root.preview

                        Repeater {
                            // 可視範囲の行だけ描画する（大きいファイルでも軽い）
                            model: area.visCount
                            delegate: Item {
                                property int lineIndex: area.visStart + index
                                property var ly: area.lineYs[lineIndex]
                                property var lh: area.lineHeights[lineIndex]
                                x: 0
                                y: ly !== undefined ? ly : 0
                                width: gutter.width
                                height: lh !== undefined ? Math.max(1, lh) : 1

                                Text {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: lineIndex + 1
                                    color: theme.muted
                                    opacity: 0.55
                                    font.family: App.monoFont
                                    font.pixelSize: Settings.fontSize - 3
                                }
                                Rectangle {
                                    visible: area.marks.indexOf(lineIndex + 1) >= 0
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
                        property int visStart: 0
                        property int visCount: 0

                        // 可視行の範囲だけを求める（ガター描画を可視分に限定するため）
                        function updateVisible() {
                            const n = lineYs.length;
                            if (n === 0) {
                                visStart = 0;
                                visCount = 0;
                                return;
                            }
                            const top = flick.contentY;
                            const bottom = top + flick.height;
                            let s = 0;
                            while (s < n && (lineYs[s] + (lineHeights[s] || 0)) < top)
                                ++s;
                            let e = s;
                            while (e < n && lineYs[e] < bottom)
                                ++e;
                            visStart = s;
                            visCount = Math.max(0, e - s);
                        }

                        // 編集のたびに全行を再計測しないようデバウンスする
                        Timer {
                            id: relayout
                            interval: 60
                            repeat: false
                            onTriggered: area.measureYs()
                        }

                        function recomputeLines() {
                            var starts = [0];
                            var t = text;
                            for (var i = 0; i < t.length; i++) {
                                if (t.charAt(i) === "\n")
                                    starts.push(i + 1);
                            }
                            lineStarts = starts;
                            relayout.restart();
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
                            updateVisible();
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

                        onContentHeightChanged: relayout.restart()
                        onWidthChanged: relayout.restart()

                        Component.onCompleted: {
                            text = model.text;
                            recomputeLines();
                            marks = Bookmarks.lineMarks(Docs.keyAt(index));
                            if (index === tabBar.currentIndex) {
                                root.activeEditor = area;
                                root.activeFlick = flick;
                                root.recomputeSearch();
                                Qt.callLater(area.forceActiveFocus);
                            }
                            const line = Bookmarks.lastPosition(Docs.keyAt(index));
                            if (line > 0)
                                Qt.callLater(function () { jumpToLine(line); });
                        }

                        onTextChanged: {
                            if (Docs.textAt(index) !== text)
                                Docs.setTextAt(index, text);
                            recomputeLines();
                            if (root.preview)
                                previewDebounce.restart();
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
                        font.family: App.monoFont
                        font.pixelSize: Settings.fontSize
                        topPadding: 16
                        bottomPadding: 16
                        leftPadding: 16
                        rightPadding: 16

                        background: Rectangle { color: theme.editorBg }

                        // カーソルが表示範囲の外に出たら追従してスクロールする
                        function ensureCursorVisible() {
                            const r = positionToRectangle(cursorPosition);
                            const margin = Math.max(24, Settings.fontSize * 2);
                            const top = flick.contentY;
                            const bottom = top + flick.height;
                            if (r.y - margin < top) {
                                flick.contentY = Math.max(0, r.y - margin);
                            } else if (r.y + r.height + margin > bottom) {
                                const maxY = Math.max(0, content.height - flick.height);
                                flick.contentY = Math.min(maxY, r.y + r.height + margin - flick.height);
                            }
                            if (!Settings.wrap) {
                                const left = flick.contentX;
                                const right = left + flick.width;
                                if (r.x - margin < left) {
                                    flick.contentX = Math.max(0, r.x - margin);
                                } else if (r.x + r.width + margin > right) {
                                    flick.contentX = Math.max(0, r.x + r.width + margin - flick.width);
                                }
                            }
                        }

                        onCursorPositionChanged: {
                            if (!activeFocus)
                                return;
                            const t = text.substring(0, cursorPosition);
                            const line = t.split("\n").length;
                            const col = t.length - t.lastIndexOf("\n");
                            root.cursorLine = line;
                            root.cursorColumn = col;
                            Bookmarks.setLastPosition(Docs.keyAt(index), line);
                            ensureCursorVisible();
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
    Shortcut { sequence: "Ctrl+N"; onActivated: root.newTab() }
    Shortcut { sequence: "Ctrl+T"; onActivated: root.newTab() }
    Shortcut {
        sequences: ["Ctrl+Tab", "Ctrl+PageDown"]
        onActivated: root.nextTab()
    }
    Shortcut {
        sequences: ["Ctrl+Shift+Tab", "Ctrl+PageUp"]
        onActivated: root.prevTab()
    }
    Shortcut { sequence: "Ctrl+O"; onActivated: openDialog.open() }
    Shortcut { sequence: "Ctrl+S"; onActivated: root.saveCurrent() }
    Shortcut { sequence: "Ctrl+Shift+S"; onActivated: root.openSaveAs(root.activeIndex) }
    Shortcut { sequence: "Ctrl+W"; onActivated: root.closeCurrent() }
    Shortcut { sequence: "Ctrl+Q"; onActivated: root.tryQuit() }
    Shortcut { sequence: "Ctrl+B"; onActivated: root.toggleLineBookmark() }
    Shortcut { sequence: "Ctrl+Shift+B"; onActivated: root.toggleFileBookmark() }
    Shortcut { sequence: "Ctrl+J"; onActivated: root.panelOpen = !root.panelOpen }
    Shortcut {
        sequences: ["Ctrl+Shift+Up", "Ctrl+=", "Ctrl+Plus", "Ctrl++"]
        onActivated: Settings.fontSize = Settings.fontSize + 1
    }
    Shortcut {
        sequences: ["Ctrl+Shift+Down", "Ctrl+-", "Ctrl+Minus"]
        onActivated: Settings.fontSize = Settings.fontSize - 1
    }
    Shortcut { sequence: "Ctrl+0"; onActivated: Settings.fontSize = 15 }
    // メニューを開いている間はウィンドウ側でもキーを処理する（フォーカス依存をなくす）
    Shortcut {
        sequences: ["Up"]
        enabled: root.openMenu !== null
        onActivated: root.openMenu.move(-1)
    }
    Shortcut {
        sequences: ["Down"]
        enabled: root.openMenu !== null
        onActivated: root.openMenu.move(1)
    }
    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: root.openMenu !== null
        onActivated: root.openMenu.activate()
    }
    Shortcut {
        sequence: "Escape"
        enabled: root.openMenu !== null
        onActivated: root.openMenu.close()
    }
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
        focus: true
        width: 440
        padding: 0
        background: Rectangle {
            color: theme.surface
            radius: 12
            border.width: 1
            border.color: theme.border
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#99000000"
                shadowBlur: 1.0
                shadowVerticalOffset: 8
                shadowHorizontalOffset: 0
            }
        }

        // カーソルキーで選んでいるボタン
        property int sel: 0
        readonly property var actions: [
            function () { closeConfirm.close(); root.saveCurrent(); root.doClose(); },
            function () { closeConfirm.close(); root.doClose(); },
            function () { closeConfirm.close(); }
        ]
        function moveSel(d) { sel = (sel + d + actions.length) % actions.length; }
        function runSel() { const f = actions[sel]; if (f) f(); }

        onOpened: {
            sel = 0;
            closeFooter.forceActiveFocus();
            Qt.callLater(function () { closeFooter.forceActiveFocus(); });
        }
        onClosed: {
            if (root.activeEditor)
                root.activeEditor.forceActiveFocus();
        }

        header: Item {
            implicitHeight: 54
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                text: root.tr("unsavedTitle")
                color: theme.text
                font.family: root.font.family
                font.pixelSize: 16
                font.bold: true
            }
        }

        contentItem: Text {
            leftPadding: 22
            rightPadding: 22
            topPadding: 0
            bottomPadding: 10
            text: root.tr("unsavedBody").replace("%1", root.titleOf(root.pendingClose))
            color: theme.muted
            font.family: root.font.family
            font.pixelSize: 14
            wrapMode: Text.WordWrap
        }

        footer: Item {
            id: closeFooter
            implicitHeight: 62
            focus: true
            Keys.onLeftPressed: closeConfirm.moveSel(-1)
            Keys.onUpPressed: closeConfirm.moveSel(-1)
            Keys.onRightPressed: closeConfirm.moveSel(1)
            Keys.onDownPressed: closeConfirm.moveSel(1)
            Keys.onTabPressed: closeConfirm.moveSel(1)
            Keys.onBacktabPressed: closeConfirm.moveSel(-1)
            Keys.onReturnPressed: closeConfirm.runSel()
            Keys.onEnterPressed: closeConfirm.runSel()
            Keys.onEscapePressed: closeConfirm.close()

            RowLayout {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                FlatButton {
                    text: root.tr("save")
                    primaryColor: theme.accent
                    selected: closeConfirm.sel === 0
                    onClicked: closeConfirm.actions[0]()
                }
                FlatButton {
                    text: root.tr("dontSave")
                    textColor: theme.text
                    hoverColor: theme.hover
                    primaryColor: theme.accent
                    selected: closeConfirm.sel === 1
                    onClicked: closeConfirm.actions[1]()
                }
                FlatButton {
                    text: root.tr("cancel")
                    textColor: theme.text
                    hoverColor: theme.hover
                    primaryColor: theme.accent
                    selected: closeConfirm.sel === 2
                    onClicked: closeConfirm.actions[2]()
                }
            }
        }
    }

    Dialog {
        id: quitConfirm
        anchors.centerIn: parent
        modal: true
        popupType: Popup.Item
        focus: true
        width: 440
        padding: 0
        background: Rectangle {
            color: theme.surface
            radius: 12
            border.width: 1
            border.color: theme.border
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#99000000"
                shadowBlur: 1.0
                shadowVerticalOffset: 8
                shadowHorizontalOffset: 0
            }
        }

        // カーソルキーで選んでいるボタン
        property int sel: 0
        readonly property var actions: [
            function () { quitConfirm.close(); Docs.saveAll(); root.quitting = true; Qt.quit(); },
            function () { quitConfirm.close(); root.quitting = true; Qt.quit(); },
            function () { quitConfirm.close(); }
        ]
        function moveSel(d) { sel = (sel + d + actions.length) % actions.length; }
        function runSel() { const f = actions[sel]; if (f) f(); }

        onOpened: {
            sel = 0;
            quitFooter.forceActiveFocus();
            Qt.callLater(function () { quitFooter.forceActiveFocus(); });
        }

        header: Item {
            implicitHeight: 54
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                text: root.tr("quitTitle")
                color: theme.text
                font.family: root.font.family
                font.pixelSize: 16
                font.bold: true
            }
        }

        contentItem: Text {
            leftPadding: 22
            rightPadding: 22
            topPadding: 0
            bottomPadding: 10
            text: root.tr("quitBody")
            color: theme.muted
            font.family: root.font.family
            font.pixelSize: 14
            wrapMode: Text.WordWrap
        }

        footer: Item {
            id: quitFooter
            implicitHeight: 62
            focus: true
            Keys.onLeftPressed: quitConfirm.moveSel(-1)
            Keys.onUpPressed: quitConfirm.moveSel(-1)
            Keys.onRightPressed: quitConfirm.moveSel(1)
            Keys.onDownPressed: quitConfirm.moveSel(1)
            Keys.onTabPressed: quitConfirm.moveSel(1)
            Keys.onBacktabPressed: quitConfirm.moveSel(-1)
            Keys.onReturnPressed: quitConfirm.runSel()
            Keys.onEnterPressed: quitConfirm.runSel()
            Keys.onEscapePressed: quitConfirm.close()

            RowLayout {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                FlatButton {
                    text: root.tr("saveAndQuit")
                    primaryColor: theme.accent
                    selected: quitConfirm.sel === 0
                    onClicked: quitConfirm.actions[0]()
                }
                FlatButton {
                    text: root.tr("quitNoSave")
                    textColor: theme.text
                    hoverColor: theme.hover
                    primaryColor: theme.accent
                    selected: quitConfirm.sel === 1
                    onClicked: quitConfirm.actions[1]()
                }
                FlatButton {
                    text: root.tr("cancel")
                    textColor: theme.text
                    hoverColor: theme.hover
                    primaryColor: theme.accent
                    selected: quitConfirm.sel === 2
                    onClicked: quitConfirm.actions[2]()
                }
            }
        }
    }

    // ダイアログの共通設定は各 Dialog に直接書いている（Component は background に代入できないため）

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
