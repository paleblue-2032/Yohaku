#include "backend.h"

#include <QQuickTextDocument>
#include <QTextBlock>
#include <QTextCursor>
#include <QTextDocument>
#include <QTextFrame>
#include <QTextTable>

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalServer>
#include <QLocalSocket>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTextStream>

namespace {

QString configDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
           + QStringLiteral("/yohaku");
}

QString stateDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation)
           + QStringLiteral("/yohaku");
}

QJsonObject readJson(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(f.readAll()).object();
}

void writeJson(const QString &path, const QJsonObject &obj)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly))
        return;
    f.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    f.commit();
}

} // namespace

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

Settings::Settings(QObject *parent) : QObject(parent) {}

QString Settings::filePath()
{
    return configDir() + QStringLiteral("/settings.json");
}

void Settings::load()
{
    const QJsonObject o = readJson(filePath());
    m_language = o.value(QStringLiteral("language")).toString(QStringLiteral("en"));
    m_dark = o.value(QStringLiteral("dark")).toBool(true);
    m_accent = o.value(QStringLiteral("accent")).toString(QStringLiteral("#4cc2ff"));
    if (!m_accent.startsWith(QLatin1Char('#'))) {
        // 旧バージョンは色名で保存していたので hex に移行する
        static const QHash<QString, QString> names = {
            { QStringLiteral("Amber"), QStringLiteral("#e6b450") },
            { QStringLiteral("Blue"), QStringLiteral("#4cc2ff") },
            { QStringLiteral("Green"), QStringLiteral("#5fbf7f") },
            { QStringLiteral("Pink"), QStringLiteral("#e07a9a") },
            { QStringLiteral("Purple"), QStringLiteral("#a98bf0") },
        };
        m_accent = names.value(m_accent, QStringLiteral("#4cc2ff"));
    }
    m_fontSize = o.value(QStringLiteral("fontSize")).toInt(15);
    m_wrap = o.value(QStringLiteral("wrap")).toBool(true);
    m_lineNumbers = o.value(QStringLiteral("lineNumbers")).toBool(true);
    m_windowOpacity = qBound(0.4, o.value(QStringLiteral("windowOpacity")).toDouble(0.9), 1.0);
    m_previewFont = o.value(QStringLiteral("previewFont")).toString(QStringLiteral("sans"));
    emit languageChanged();
    emit darkChanged();
    emit accentChanged();
    emit fontSizeChanged();
    emit wrapChanged();
    emit lineNumbersChanged();
    emit windowOpacityChanged();
    emit previewFontChanged();
}

void Settings::save() const
{
    // 他の項目（keymap など）を消さないように既存の内容を読み込んでから更新する
    QJsonObject o = readJson(filePath());
    o.insert(QStringLiteral("language"), m_language);
    o.insert(QStringLiteral("dark"), m_dark);
    o.insert(QStringLiteral("accent"), m_accent);
    o.insert(QStringLiteral("fontSize"), m_fontSize);
    o.insert(QStringLiteral("wrap"), m_wrap);
    o.insert(QStringLiteral("lineNumbers"), m_lineNumbers);
    o.insert(QStringLiteral("windowOpacity"), m_windowOpacity);
    o.insert(QStringLiteral("previewFont"), m_previewFont);
    writeJson(filePath(), o);
}

void Settings::setLanguage(const QString &v)
{
    if (m_language == v)
        return;
    m_language = v;
    emit languageChanged();
}

void Settings::setDark(bool v)
{
    if (m_dark == v)
        return;
    m_dark = v;
    emit darkChanged();
}

void Settings::setAccent(const QString &v)
{
    if (m_accent == v)
        return;
    m_accent = v;
    emit accentChanged();
}

void Settings::setFontSize(int v)
{
    v = qBound(8, v, 48);
    if (m_fontSize == v)
        return;
    m_fontSize = v;
    emit fontSizeChanged();
}

void Settings::setWindowOpacity(qreal v)
{
    v = qBound(0.4, v, 1.0);
    if (qFuzzyCompare(m_windowOpacity, v))
        return;
    m_windowOpacity = v;
    emit windowOpacityChanged();
}

void Settings::setPreviewFont(const QString &v)
{
    if (m_previewFont == v)
        return;
    m_previewFont = v;
    emit previewFontChanged();
}

void Settings::setWrap(bool v)
{
    if (m_wrap == v)
        return;
    m_wrap = v;
    emit wrapChanged();
}

void Settings::setLineNumbers(bool v)
{
    if (m_lineNumbers == v)
        return;
    m_lineNumbers = v;
    emit lineNumbersChanged();
}

// ---------------------------------------------------------------------------
// Keymap
// ---------------------------------------------------------------------------

namespace {

const QHash<QString, QStringList> &defaultKeymap()
{
    static const QHash<QString, QStringList> defaults = {
        { QStringLiteral("newTab"), { QStringLiteral("Ctrl+T"), QStringLiteral("Ctrl+N") } },
        { QStringLiteral("open"), { QStringLiteral("Ctrl+O") } },
        { QStringLiteral("save"), { QStringLiteral("Ctrl+S") } },
        { QStringLiteral("saveAs"), { QStringLiteral("Ctrl+Shift+S") } },
        { QStringLiteral("closeTab"), { QStringLiteral("Ctrl+W") } },
        { QStringLiteral("quit"), { QStringLiteral("Ctrl+Q") } },
        { QStringLiteral("find"), { QStringLiteral("Ctrl+F") } },
        { QStringLiteral("preview"), { QStringLiteral("Ctrl+P") } },
        { QStringLiteral("undo"), { QStringLiteral("Ctrl+Z") } },
        { QStringLiteral("redo"), { QStringLiteral("Ctrl+Y") } },
        { QStringLiteral("bookmarkLine"), { QStringLiteral("Ctrl+B") } },
        { QStringLiteral("bookmarkFile"), { QStringLiteral("Ctrl+Shift+B") } },
        { QStringLiteral("bookmarkPanel"), { QStringLiteral("Ctrl+J") } },
        { QStringLiteral("nextTab"), { QStringLiteral("Ctrl+Tab"), QStringLiteral("Ctrl+PageDown") } },
        { QStringLiteral("prevTab"), { QStringLiteral("Ctrl+Shift+Tab"), QStringLiteral("Ctrl+PageUp") } },
    };
    return defaults;
}

} // namespace

Keymap::Keymap(QObject *parent) : QObject(parent) {}

QString Keymap::filePath()
{
    // 設定は 1 ファイルにまとめる（settings.json の "keymap" セクション）
    return configDir() + QStringLiteral("/settings.json");
}

void Keymap::load()
{
    m_map = defaultKeymap();

    const QJsonObject root = readJson(filePath());
    const QJsonObject o = root.value(QStringLiteral("keymap")).toObject();
    if (o.isEmpty()) {
        writeDefault(); // "keymap" が無ければ雛形を書き出す
        return;
    }
    for (auto it = o.begin(); it != o.end(); ++it) {
        if (it.key().startsWith(QLatin1Char('_')))
            continue; // コメント用のキー
        QStringList keys;
        if (it.value().isArray()) {
            for (const QJsonValue &v : it.value().toArray()) {
                if (v.isString() && !v.toString().isEmpty())
                    keys << v.toString();
            }
        } else if (it.value().isString() && !it.value().toString().isEmpty()) {
            keys << it.value().toString();
        }
        if (!keys.isEmpty())
            m_map.insert(it.key(), keys);
        else
            m_map.remove(it.key()); // 空にすると割り当てを外せる
    }
    ++m_rev;
    emit changed();
}

void Keymap::watch()
{
    if (m_watcher)
        return;
    m_watcher = new QFileSystemWatcher(this);
    const QString path = filePath();
    m_watcher->addPath(path);
    connect(m_watcher, &QFileSystemWatcher::fileChanged, this, [this, path]() {
        load();
        if (!m_watcher->files().contains(path))
            m_watcher->addPath(path);
    });
}

void Keymap::writeDefault() const
{
    QJsonObject o;
    o.insert(QStringLiteral("_comment"),
             QStringLiteral("Yohaku のキー設定。値は文字列か配列。空にすると割り当てを外せます。"
                            "文字サイズの Ctrl+= / Ctrl+- / Ctrl+0 はキー配列に依存せず動作します。"));
    const auto &defaults = defaultKeymap();
    for (auto it = defaults.begin(); it != defaults.end(); ++it)
        o.insert(it.key(), QJsonArray::fromStringList(it.value()));

    // settings.json の "keymap" に書き込む（他の設定は保持）
    QJsonObject root = readJson(filePath());
    root.insert(QStringLiteral("keymap"), o);
    writeJson(filePath(), root);
}

QStringList Keymap::seq(const QString &action) const
{
    return m_map.value(action);
}

QString Keymap::primary(const QString &action) const
{
    const QStringList keys = m_map.value(action);
    return keys.isEmpty() ? QString() : keys.first();
}

// ---------------------------------------------------------------------------
// I18n
// ---------------------------------------------------------------------------

I18n::I18n(Settings *settings, QObject *parent) : QObject(parent), m_settings(settings)
{
    const auto add = [](QHash<QString, QString> &m, const char *k, const char *v) {
        m.insert(QString::fromUtf8(k), QString::fromUtf8(v));
    };

    add(m_en, "file", "File");
    add(m_en, "view", "View");
    add(m_en, "settings", "Settings");
    add(m_en, "bookmarks", "Bookmarks");
    add(m_en, "new", "New");
    add(m_en, "open", "Open…");
    add(m_en, "save", "Save");
    add(m_en, "saveAs", "Save As…");
    add(m_en, "closeTab", "Close Tab");
    add(m_en, "quit", "Quit");
    add(m_en, "wordWrap", "Word Wrap");
    add(m_en, "lineNumbers", "Line Numbers");
    add(m_en, "preview", "Markdown Preview");
    add(m_en, "find", "Find…");
    add(m_en, "findHint", "Search");
    add(m_en, "prev", "Prev");
    add(m_en, "next", "Next");
    add(m_en, "close", "Close");
    add(m_en, "theme", "Theme");
    add(m_en, "dark", "Dark");
    add(m_en, "light", "Light");
    add(m_en, "accent", "Accent Color");
    add(m_en, "transparency", "Transparency");
    add(m_en, "opacityNone", "None (opaque)");
    add(m_en, "opacityLight", "Light");
    add(m_en, "opacityMedium", "Medium");
    add(m_en, "opacityStrong", "Strong");
    add(m_en, "previewFont", "Preview Font");
    add(m_en, "fontSans", "Sans Serif");
    add(m_en, "fontSerif", "Serif");
    add(m_en, "fontMono", "Monospace");
    add(m_en, "fontSize", "Font Size");
    add(m_en, "language", "Language");
    add(m_en, "bookmarkLine", "Toggle Bookmark on This Line");
    add(m_en, "bookmarkFileAdd", "Bookmark This File");
    add(m_en, "bookmarkFileRemove", "Remove File Bookmark");
    add(m_en, "bookmarkPanel", "Bookmarks Panel");
    add(m_en, "thisFileBookmarks", "Bookmarks in this file");
    add(m_en, "fileBookmarks", "File bookmarks");
    add(m_en, "noLineBookmarks", "(Ctrl+B to bookmark a line)");
    add(m_en, "noFileBookmarks", "(Ctrl+Shift+B to add)");
    add(m_en, "untitled", "Untitled");
    add(m_en, "line", "line");
    add(m_en, "col", "col");
    add(m_en, "placeholder", "Start typing…");
    add(m_en, "emptyHint", "Open a file (Ctrl+O) or create a new one (Ctrl+N)");
    add(m_en, "unsavedTitle", "Unsaved changes");
    add(m_en, "unsavedBody", "Save changes to “%1”?");
    add(m_en, "dontSave", "Don’t Save");
    add(m_en, "cancel", "Cancel");
    add(m_en, "quitTitle", "Unsaved changes");
    add(m_en, "quitBody", "You have unsaved changes. Quit anyway?");
    add(m_en, "saveAndQuit", "Save and Quit");
    add(m_en, "quitNoSave", "Quit Without Saving");
    add(m_en, "saved", "Saved");
    add(m_en, "openFailed", "Could not open %1");
    add(m_en, "wrap", "Wrap");
    add(m_en, "noWrap", "No Wrap");

    add(m_ja, "file", "ファイル");
    add(m_ja, "view", "表示");
    add(m_ja, "settings", "設定");
    add(m_ja, "bookmarks", "栞");
    add(m_ja, "new", "新規");
    add(m_ja, "open", "開く…");
    add(m_ja, "save", "保存");
    add(m_ja, "saveAs", "名前を付けて保存…");
    add(m_ja, "closeTab", "タブを閉じる");
    add(m_ja, "quit", "終了");
    add(m_ja, "wordWrap", "折り返し");
    add(m_ja, "lineNumbers", "行番号");
    add(m_ja, "preview", "Markdown プレビュー");
    add(m_ja, "find", "検索…");
    add(m_ja, "findHint", "検索語");
    add(m_ja, "prev", "前");
    add(m_ja, "next", "次");
    add(m_ja, "close", "閉じる");
    add(m_ja, "theme", "テーマ");
    add(m_ja, "dark", "ダーク");
    add(m_ja, "light", "ライト");
    add(m_ja, "accent", "アクセントカラー");
    add(m_ja, "transparency", "透過");
    add(m_ja, "opacityNone", "なし（不透明）");
    add(m_ja, "opacityLight", "弱");
    add(m_ja, "opacityMedium", "中");
    add(m_ja, "opacityStrong", "強");
    add(m_ja, "previewFont", "プレビューのフォント");
    add(m_ja, "fontSans", "サンセリフ");
    add(m_ja, "fontSerif", "セリフ");
    add(m_ja, "fontMono", "等幅");
    add(m_ja, "fontSize", "文字サイズ");
    add(m_ja, "language", "言語");
    add(m_ja, "bookmarkLine", "この行に栞を挟む/外す");
    add(m_ja, "bookmarkFileAdd", "このファイルを栞に追加");
    add(m_ja, "bookmarkFileRemove", "ファイル栞から外す");
    add(m_ja, "bookmarkPanel", "栞パネル");
    add(m_ja, "thisFileBookmarks", "このファイルの栞");
    add(m_ja, "fileBookmarks", "ファイル栞");
    add(m_ja, "noLineBookmarks", "（Ctrl+B でこの行に栞）");
    add(m_ja, "noFileBookmarks", "（Ctrl+Shift+B で追加）");
    add(m_ja, "untitled", "無題");
    add(m_ja, "line", "行");
    add(m_ja, "col", "列");
    add(m_ja, "placeholder", "入力してください…");
    add(m_ja, "emptyHint", "ファイルを開く（Ctrl+O）か、Ctrl+N で新規作成");
    add(m_ja, "unsavedTitle", "未保存の変更");
    add(m_ja, "unsavedBody", "「%1」を保存しますか？");
    add(m_ja, "dontSave", "保存しない");
    add(m_ja, "cancel", "キャンセル");
    add(m_ja, "quitTitle", "未保存の変更があります");
    add(m_ja, "quitBody", "保存していない変更があります。終了しますか？");
    add(m_ja, "saveAndQuit", "保存して終了");
    add(m_ja, "quitNoSave", "保存せず終了");
    add(m_ja, "saved", "保存しました");
    add(m_ja, "openFailed", "開けません: %1");
    add(m_ja, "wrap", "折り返し");
    add(m_ja, "noWrap", "折り返しなし");

    connect(m_settings, &Settings::languageChanged, this, [this]() {
        ++m_rev;
        emit changed();
    });
}

QString I18n::t(const QString &key) const
{
    const QHash<QString, QString> &m =
        (m_settings->language() == QStringLiteral("ja")) ? m_ja : m_en;
    return m.value(key, key);
}

// ---------------------------------------------------------------------------
// Bookmarks
// ---------------------------------------------------------------------------

Bookmarks::Bookmarks(QObject *parent) : QObject(parent) {}

QString Bookmarks::filePath()
{
    return stateDir() + QStringLiteral("/bookmarks.json");
}

void Bookmarks::load()
{
    const QJsonObject o = readJson(filePath());
    m_last.clear();
    const QJsonObject last = o.value(QStringLiteral("last")).toObject();
    for (auto it = last.begin(); it != last.end(); ++it)
        m_last.insert(it.key(), it.value().toInt());

    m_lines.clear();
    const QJsonObject lines = o.value(QStringLiteral("lines")).toObject();
    for (auto it = lines.begin(); it != lines.end(); ++it) {
        QVariantList list;
        for (const QJsonValue &v : it.value().toArray())
            list.append(v.toInt());
        m_lines.insert(it.key(), list);
    }

    m_files = o.value(QStringLiteral("files")).toArray().toVariantList();
    ++m_rev;
    emit changed();
}

void Bookmarks::save()
{
    QJsonObject last;
    for (auto it = m_last.begin(); it != m_last.end(); ++it)
        last.insert(it.key(), it.value());

    QJsonObject lines;
    for (auto it = m_lines.begin(); it != m_lines.end(); ++it) {
        QJsonArray arr;
        for (const QVariant &v : it.value())
            arr.append(v.toInt());
        lines.insert(it.key(), arr);
    }

    QJsonObject o;
    o.insert(QStringLiteral("last"), last);
    o.insert(QStringLiteral("lines"), lines);
    o.insert(QStringLiteral("files"), QJsonArray::fromVariantList(m_files));
    writeJson(filePath(), o);
}

int Bookmarks::lastPosition(const QString &key) const
{
    return m_last.value(key, 0);
}

void Bookmarks::setLastPosition(const QString &key, int line)
{
    if (key.isEmpty())
        return;
    if (m_last.value(key, -1) == line)
        return;
    m_last.insert(key, line);
}

QVariantList Bookmarks::lineMarks(const QString &key) const
{
    return m_lines.value(key);
}

void Bookmarks::setLineMarks(const QString &key, const QVariantList &marks)
{
    if (marks.isEmpty())
        m_lines.remove(key);
    else
        m_lines.insert(key, marks);
    ++m_rev;
    emit changed();
}

bool Bookmarks::isFileBookmarked(const QString &key) const
{
    for (const QVariant &v : m_files) {
        if (v.toMap().value(QStringLiteral("key")).toString() == key)
            return true;
    }
    return false;
}

bool Bookmarks::toggleFile(const QString &key, const QString &title, const QString &path)
{
    for (int i = 0; i < m_files.size(); ++i) {
        if (m_files.at(i).toMap().value(QStringLiteral("key")).toString() == key) {
            m_files.removeAt(i);
            ++m_rev;
    emit changed();
            return false;
        }
    }
    QVariantMap m;
    m.insert(QStringLiteral("key"), key);
    m.insert(QStringLiteral("title"), title);
    m.insert(QStringLiteral("path"), path);
    m_files.append(m);
    ++m_rev;
    emit changed();
    return true;
}

void Bookmarks::removeFile(const QString &key)
{
    for (int i = 0; i < m_files.size(); ++i) {
        if (m_files.at(i).toMap().value(QStringLiteral("key")).toString() == key) {
            m_files.removeAt(i);
            ++m_rev;
    emit changed();
            return;
        }
    }
}

// ---------------------------------------------------------------------------
// DocumentModel
// ---------------------------------------------------------------------------

DocumentModel::DocumentModel(Bookmarks *bookmarks, QObject *parent)
    : QAbstractListModel(parent), m_bookmarks(bookmarks)
{
}

QString DocumentModel::keyOf(const Doc &doc) const
{
    if (!doc.path.isEmpty())
        return doc.path;
    return doc.draftId;
}

int DocumentModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_docs.size();
}

QHash<int, QByteArray> DocumentModel::roleNames() const
{
    return {
        { TitleRole, "title" },
        { TextRole, "text" },
        { PathRole, "path" },
        { ModifiedRole, "modified" },
        { KeyRole, "key" },
    };
}

QVariant DocumentModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_docs.size())
        return {};
    const Doc &d = m_docs.at(index.row());
    switch (role) {
    case TitleRole:
        return d.path.isEmpty() ? QString() : d.title;
    case TextRole:
        return d.text;
    case PathRole:
        return d.path;
    case ModifiedRole:
        return d.modified;
    case KeyRole:
        return keyOf(d);
    default:
        return {};
    }
}

int DocumentModel::indexOfPath(const QString &path) const
{
    for (int i = 0; i < m_docs.size(); ++i) {
        if (!m_docs.at(i).path.isEmpty() && m_docs.at(i).path == path)
            return i;
    }
    return -1;
}

int DocumentModel::addUntitled()
{
    Doc d;
    d.draftId = QStringLiteral("untitled-%1").arg(QDateTime::currentMSecsSinceEpoch());
    beginInsertRows(QModelIndex(), m_docs.size(), m_docs.size());
    m_docs.append(d);
    endInsertRows();
    emit countChanged();
    return m_docs.size() - 1;
}

int DocumentModel::openPath(const QString &path)
{
    const QString canonical = QFileInfo(path).canonicalFilePath().isEmpty()
                                  ? path
                                  : QFileInfo(path).canonicalFilePath();
    const int existing = indexOfPath(canonical);
    if (existing >= 0)
        return existing;

    QFile f(canonical);
    if (!f.open(QIODevice::ReadOnly))
        return -1;

    Doc d;
    d.path = canonical;
    d.title = QFileInfo(canonical).fileName();
    d.text = QString::fromUtf8(f.readAll());
    beginInsertRows(QModelIndex(), m_docs.size(), m_docs.size());
    m_docs.append(d);
    endInsertRows();
    emit countChanged();
    return m_docs.size() - 1;
}

void DocumentModel::setTextAt(int row, const QString &text)
{
    if (row < 0 || row >= m_docs.size())
        return;
    if (m_docs[row].text == text)
        return;
    m_docs[row].text = text;
    if (!m_docs[row].modified) {
        m_docs[row].modified = true;
        emit modifiedChanged(row);
    }
    const QModelIndex idx = index(row);
    emit dataChanged(idx, idx, { TextRole, ModifiedRole });
}

QString DocumentModel::textAt(int row) const
{
    return (row >= 0 && row < m_docs.size()) ? m_docs.at(row).text : QString();
}

QString DocumentModel::titleAt(int row) const
{
    return (row >= 0 && row < m_docs.size()) ? m_docs.at(row).title : QString();
}

QString DocumentModel::keyAt(int row) const
{
    return (row >= 0 && row < m_docs.size()) ? keyOf(m_docs.at(row)) : QString();
}

QString DocumentModel::pathAt(int row) const
{
    return (row >= 0 && row < m_docs.size()) ? m_docs.at(row).path : QString();
}

bool DocumentModel::saveAt(int row)
{
    if (row < 0 || row >= m_docs.size() || m_docs[row].path.isEmpty())
        return false;
    QSaveFile f(m_docs[row].path);
    if (!f.open(QIODevice::WriteOnly))
        return false;
    f.write(m_docs[row].text.toUtf8());
    if (!f.commit())
        return false;
    m_docs[row].modified = false;
    // QML 側は model.modified / model.title を見ているので dataChanged も必要
    const QModelIndex idx = index(row);
    emit dataChanged(idx, idx, { TitleRole, PathRole, ModifiedRole, KeyRole });
    emit modifiedChanged(row);
    return true;
}

bool DocumentModel::saveAsAt(int row, const QUrl &url)
{
    if (row < 0 || row >= m_docs.size())
        return false;
    const QString path = url.toLocalFile();
    if (path.isEmpty())
        return false;

    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly))
        return false;
    f.write(m_docs[row].text.toUtf8());
    if (!f.commit())
        return false;

    m_docs[row].path = path;
    m_docs[row].title = QFileInfo(path).fileName();
    m_docs[row].draftId.clear();
    m_docs[row].modified = false;
    const QModelIndex idx = index(row);
    emit dataChanged(idx, idx, { TitleRole, PathRole, ModifiedRole, KeyRole });
    emit modifiedChanged(row);
    return true;
}

bool DocumentModel::isModifiedAt(int row) const
{
    return row >= 0 && row < m_docs.size() && m_docs.at(row).modified;
}

bool DocumentModel::anyModified() const
{
    for (const Doc &d : m_docs) {
        if (d.modified)
            return true;
    }
    return false;
}

void DocumentModel::saveAll()
{
    for (int i = 0; i < m_docs.size(); ++i) {
        if (m_docs[i].modified && !m_docs[i].path.isEmpty())
            saveAt(i);
    }
}

void DocumentModel::closeAt(int row)
{
    if (row < 0 || row >= m_docs.size())
        return;
    beginRemoveRows(QModelIndex(), row, row);
    m_docs.remove(row);
    endRemoveRows();
    emit countChanged();
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

App::App(DocumentModel *docs, Settings *settings, Bookmarks *bookmarks, QObject *parent)
    : QObject(parent), m_docs(docs), m_settings(settings), m_bookmarks(bookmarks)
{
    // プラットフォームごとに日本語が出せる UI フォントを選ぶ
    const QStringList candidates = {
        QStringLiteral("Noto Sans CJK JP"),
        QStringLiteral("Noto Sans JP"),
        QStringLiteral("BIZ UDPGothic"),
        QStringLiteral("Hiragino Sans"),
        QStringLiteral("Yu Gothic UI"),
        QStringLiteral("Meiryo"),
        QStringLiteral("Source Han Sans JP"),
        QStringLiteral("IPAGothic"),
    };
    const QStringList families = QFontDatabase::families();
    for (const QString &c : candidates) {
        if (families.contains(c, Qt::CaseInsensitive)) {
            m_uiFont = c;
            break;
        }
    }
    if (m_uiFont.isEmpty())
        m_uiFont = QGuiApplication::font().family();

    // 本文表示は等幅フォント。日本語も等幅で揃うものを優先し、
    // 無ければ各 OS で一般的な等幅フォントにフォールバックする。
    const QStringList monoCandidates = {
        QStringLiteral("Noto Sans Mono CJK JP"),
        QStringLiteral("Noto Sans Mono"),
        QStringLiteral("JetBrains Mono"),
        QStringLiteral("Fira Code"),
        QStringLiteral("Cascadia Mono"),
        QStringLiteral("SF Mono"),
        QStringLiteral("Menlo"),
        QStringLiteral("Consolas"),
        QStringLiteral("DejaVu Sans Mono"),
        QStringLiteral("Liberation Mono"),
        QStringLiteral("monospace"),
    };
    for (const QString &c : monoCandidates) {
        if (!QFontDatabase::families().contains(c, Qt::CaseInsensitive)) {
            // 最後の "monospace" はファミリ名でなくても総称名として有効
            if (c != QLatin1String("monospace"))
                continue;
        }
        m_monoFont = c;
        break;
    }
    if (m_monoFont.isEmpty())
        m_monoFont = QFontDatabase::systemFont(QFontDatabase::FixedFont).family();
}

// ---------------------------------------------------------------------------
// Markdown プレビュー（GitHub 風の見た目に整形する）
// ---------------------------------------------------------------------------

namespace {

qreal headingScale(int level)
{
    switch (level) {
    case 1: return 1.65;
    case 2: return 1.38;
    case 3: return 1.18;
    case 4: return 1.06;
    default: return 1.0;
    }
}

void styleTablesRecursive(QTextDocument *doc, QTextFrame *frame, const QColor &border,
                          const QColor &headBg, const QColor &fg, qreal base, const QString &font)
{
    for (QTextFrame *child : frame->childFrames()) {
        if (auto *table = qobject_cast<QTextTable *>(child)) {
            QTextTableFormat tf = table->format();
            tf.setBorder(1);
            tf.setBorderBrush(border);
            tf.setBorderStyle(QTextFrameFormat::BorderStyle_Solid);
            tf.setCellPadding(6);
            tf.setCellSpacing(0);
            tf.setMargin(base * 0.6);
            table->setFormat(tf);

            // Qt の Markdown 表解析は先頭セルに空ブロックを入れることがあるので取り除く
            for (int row = 0; row < table->rows(); ++row) {
                for (int col = 0; col < table->columns(); ++col) {
                    QTextTableCell cell = table->cellAt(row, col);
                    if (!cell.isValid())
                        continue;
                    int count = 0;
                    for (auto it = cell.begin(); it != cell.end(); ++it)
                        if (it.currentBlock().isValid())
                            ++count;
                    if (count < 2)
                        continue;
                    // 先頭が空なら削除
                    for (auto it = cell.begin(); it != cell.end(); ++it) {
                        QTextBlock block = it.currentBlock();
                        if (!block.isValid())
                            continue;
                        if (block.text().trimmed().isEmpty()) {
                            QTextCursor del(doc);
                            del.setPosition(block.position());
                            del.setPosition(block.position() + block.length(), QTextCursor::KeepAnchor);
                            del.removeSelectedText();
                        }
                        break;   // 先頭ブロックだけ見る
                    }
                }
            }

            // 先頭行はヘッダとして背景を付ける
            if (table->rows() > 0) {
                for (int col = 0; col < table->columns(); ++col) {
                    QTextTableCell cell = table->cellAt(0, col);
                    if (!cell.isValid())
                        continue;
                    QTextCharFormat cf;
                    cf.setFontWeight(QFont::Bold);
                    cf.setForeground(fg);
                    cell.setFormat(cf);
                    // 背景はブロック単位で入れる（セルの文字だけに敷くと四角からはみ出す）
                    for (auto it = cell.begin(); it != cell.end(); ++it) {
                        QTextBlock block = it.currentBlock();
                        if (!block.isValid())
                            continue;
                        QTextBlockFormat bfmt = block.blockFormat();
                        bfmt.setBackground(headBg);
                        bfmt.setTopMargin(3);
                        bfmt.setBottomMargin(3);
                        QTextCursor bc(doc);
                        bc.setPosition(block.position());
                        bc.setBlockFormat(bfmt);
                    }
                }
            }
        }
        styleTablesRecursive(doc, child, border, headBg, fg, base, font);
    }
}

void applyBlockFormat(QTextDocument *doc, const QTextBlock &block, const QTextBlockFormat &format)
{
    QTextCursor cursor(doc);
    cursor.setPosition(block.position());
    cursor.setBlockFormat(format);
}

void selectBlock(QTextDocument *doc, const QTextBlock &block, QTextCursor &cursor)
{
    cursor = QTextCursor(doc);
    cursor.setPosition(block.position());
    cursor.setPosition(block.position() + qMax(0, block.length() - 1), QTextCursor::KeepAnchor);
}

} // namespace

QVariantList App::codeBlockRanges(QObject *edit)
{
    QVariantList out;
    if (!edit)
        return out;
    auto *qtd = qvariant_cast<QQuickTextDocument *>(edit->property("textDocument"));
    if (!qtd || !qtd->textDocument())
        return out;
    QTextDocument *doc = qtd->textDocument();

    int start = -1;
    int end = -1;
    for (QTextBlock b = doc->begin(); b.isValid(); b = b.next()) {
        const QTextBlockFormat bf = b.blockFormat();
        const bool isCode = bf.hasProperty(QTextFormat::BlockCodeFence)
                            || bf.hasProperty(QTextFormat::BlockCodeLanguage);
        if (isCode) {
            if (start < 0)
                start = b.position();
            end = b.position() + qMax(0, b.length() - 1);
        } else if (start >= 0) {
            out << QVariantMap{ { QStringLiteral("start"), start }, { QStringLiteral("end"), end } };
            start = -1;
            end = -1;
        }
    }
    if (start >= 0)
        out << QVariantMap{ { QStringLiteral("start"), start }, { QStringLiteral("end"), end } };
    return out;
}

QString App::slugifyForAnchor(const QString &text)
{
    QString out;
    for (const QChar &ch : text.trimmed().toLower()) {
        if (ch.isLetterOrNumber() || ch == QLatin1Char('_') || ch == QLatin1Char('-'))
            out.append(ch);
        else if (ch.isSpace())
            out.append(QLatin1Char('-'));
    }
    return out;
}

int App::findAnchor(QObject *edit, const QString &anchor)
{
    if (!edit)
        return -1;
    auto *qtd = qvariant_cast<QQuickTextDocument *>(edit->property("textDocument"));
    if (!qtd || !qtd->textDocument())
        return -1;
    QTextDocument *doc = qtd->textDocument();
    const QString target = slugifyForAnchor(QUrl::fromPercentEncoding(anchor.toUtf8()));
    if (target.isEmpty())
        return -1;
    for (QTextBlock b = doc->begin(); b.isValid(); b = b.next()) {
        if (b.blockFormat().headingLevel() == 0)
            continue;
        if (slugifyForAnchor(b.text()) == target)
            return b.position();
    }
    return -1;
}

void App::renderMarkdown(QObject *edit, const QString &text)
{
    if (!edit)
        return;
    auto *qtd = qvariant_cast<QQuickTextDocument *>(edit->property("textDocument"));
    if (!qtd || !qtd->textDocument())
        return;
    QTextDocument *doc = qtd->textDocument();

    const bool dark = m_settings->dark();
    const QColor fg(dark ? QStringLiteral("#e8e8e8") : QStringLiteral("#1f2328"));
    const QColor muted(dark ? QStringLiteral("#9a9a9a") : QStringLiteral("#59636e"));
    const QColor accent(m_settings->accent());
    const QColor codeBg(dark ? QStringLiteral("#2b2b2b") : QStringLiteral("#f6f8fa"));
    const QColor inlineCodeBg(dark ? QStringLiteral("#333333") : QStringLiteral("#eef1f3"));
    const QColor border(dark ? QStringLiteral("#3f3f3f") : QStringLiteral("#d1d9e0"));
    const QString monoFont = m_monoFont;

    // 本文フォント（設定で サンセリフ / セリフ / 等幅 を選べる）
    QString bodyFont = m_uiFont;
    const QString choice = m_settings->previewFont();
    if (choice == QLatin1String("mono")) {
        bodyFont = m_monoFont;
    } else if (choice == QLatin1String("serif")) {
        const QStringList serifCandidates = {
            QStringLiteral("Noto Serif CJK JP"),
            QStringLiteral("Noto Serif JP"),
            QStringLiteral("Source Han Serif JP"),
            QStringLiteral("Hiragino Mincho ProN"),
            QStringLiteral("Yu Mincho"),
        };
        const QStringList families = QFontDatabase::families();
        for (const QString &c : serifCandidates) {
            if (families.contains(c, Qt::CaseInsensitive)) {
                bodyFont = c;
                break;
            }
        }
    }

    // フォントサイズは pt、余白は px（QTextDocument はその前提で扱う）。
    // エディタ（px）と見た目の大きさを揃えるために px→pt 変換する。
    const qreal basePx = m_settings->fontSize();
    const qreal basePt = basePx * 72.0 / 96.0;

    // 見出しの直後に罫線（GitHub の h1/h2 風）を入れる。コードブロック内の "#" は無視。
    QString md;
    {
        QStringList out;
        bool fence = false;
        const QStringList lines = text.split(QLatin1Char('\n'));
        for (const QString &line : lines) {
            const QString t = line.trimmed();
            // 言語付きフェンス（```sh など）は Qt が frame で包んで背景が効かなくなるため、
            // フェンス記号だけに正規化する（言語情報は表示に使っていない）
            QString normalized = line;
            if (t.startsWith(QLatin1String("```")) || t.startsWith(QLatin1String("~~~"))) {
                const QString marker = t.startsWith(QLatin1String("```")) ? QStringLiteral("```")
                                                                          : QStringLiteral("~~~");
                const int indent = line.indexOf(t);
                normalized = line.left(indent) + marker; // 先頭の空白は残す
                fence = !fence;
            }
            out << normalized;
            if (!fence && (t.startsWith(QLatin1String("# ")) || t.startsWith(QLatin1String("## "))))
                out << QString() << QStringLiteral("---");
        }
        md = out.join(QLatin1Char('\n'));
    }

    doc->setDocumentMargin(0);
    doc->setMarkdown(md, QTextDocument::MarkdownDialectGitHub);

    // 1) 本文の既定フォント（太字/斜体は Qt にフォント選択させる。family を
    //    フラグメント単位で上書きすると CJK の太字が合成になり詰まって見える）
    {
        QFont def(bodyFont);
        def.setPointSizeF(basePt);
        doc->setDefaultFont(def);

        QTextCursor c(doc);
        c.select(QTextCursor::Document);
        QTextCharFormat f;
        f.setFontPointSize(basePt);
        f.setForeground(fg);
        c.mergeCharFormat(f);
    }

    // 2) ブロック単位: 見出し / コードブロック / 引用 / 水平線
    for (QTextBlock b = doc->begin(); b.isValid(); b = b.next()) {
        QTextBlockFormat bf = b.blockFormat();
        const int heading = bf.headingLevel();
        const bool codeBlock = bf.hasProperty(QTextFormat::BlockCodeFence)
                               || bf.hasProperty(QTextFormat::BlockCodeLanguage);
        const int quote = bf.intProperty(QTextFormat::BlockQuoteLevel);

        if (heading > 0) {
            bf.setTopMargin(basePx * (heading == 1 ? 0.9 : 0.8));
            bf.setBottomMargin(basePx * 0.35);
            applyBlockFormat(doc, b, bf);
            QTextCursor c;
            selectBlock(doc, b, c);
            QTextCharFormat f;
            f.setFontPointSize(basePt * headingScale(heading));
            f.setFontWeight(QFont::Bold);
            c.mergeCharFormat(f);
            continue;
        }
        if (codeBlock) {
            bf.setBackground(codeBg);
            // Markdown のコードブロックは既定で折り返さないため、長い行がはみ出す。
            bf.setNonBreakableLines(false);
            bf.setLeftMargin(basePx * 0.7);
            bf.setRightMargin(basePx * 0.7);
            // 上下の余白は最初/最後の行にだけ入れる（各行に入れると網掛けが途切れる）
            const bool firstLine = !b.previous().isValid()
                                   || !(b.previous().blockFormat().hasProperty(QTextFormat::BlockCodeFence)
                                        || b.previous().blockFormat().hasProperty(QTextFormat::BlockCodeLanguage));
            const bool lastLine = !b.next().isValid()
                                  || !(b.next().blockFormat().hasProperty(QTextFormat::BlockCodeFence)
                                       || b.next().blockFormat().hasProperty(QTextFormat::BlockCodeLanguage));
            bf.setTopMargin(firstLine ? basePx * 0.45 : 0);
            bf.setBottomMargin(lastLine ? basePx * 0.45 : 0);
            applyBlockFormat(doc, b, bf);
            QTextCursor c;
            selectBlock(doc, b, c);
            QTextCharFormat f;
            f.setFontFamilies({ monoFont });
            f.setFontPointSize(basePt * 0.95);
            f.setForeground(fg);
            c.mergeCharFormat(f);
            continue;
        }
        if (quote > 0) {
            bf.setLeftMargin(basePx * 1.2);
            bf.setRightMargin(basePx * 0.4);
            bf.setBottomMargin(basePx * 0.2);
            applyBlockFormat(doc, b, bf);
            QTextCursor c;
            selectBlock(doc, b, c);
            QTextCharFormat f;
            f.setForeground(muted);
            c.mergeCharFormat(f);
            continue;
        }
        if (bf.hasProperty(QTextFormat::BlockTrailingHorizontalRulerWidth)) {
            bf.setTopMargin(basePx * 0.5);
            bf.setBottomMargin(basePx * 0.7);
            applyBlockFormat(doc, b, bf);
            QTextCursor c;
            selectBlock(doc, b, c);
            QTextCharFormat f;
            f.setForeground(border);
            c.mergeCharFormat(f);
            continue;
        }
        // 通常の段落は少しだけ下に余白
        bf.setBottomMargin(basePx * 0.25);
        applyBlockFormat(doc, b, bf);
    }

    // 3) インラインコードとリンク
    for (QTextBlock b = doc->begin(); b.isValid(); b = b.next()) {
        for (auto it = b.begin(); !it.atEnd(); ++it) {
            const QTextFragment frag = it.fragment();
            if (!frag.isValid())
                continue;
            const QTextCharFormat cf = frag.charFormat();
            if (cf.isAnchor()) {
                QTextCursor c(doc);
                c.setPosition(frag.position());
                c.setPosition(frag.position() + frag.length(), QTextCursor::KeepAnchor);
                QTextCharFormat f;
                f.setForeground(accent);
                f.setFontUnderline(true);
                c.mergeCharFormat(f);
            } else if (cf.fontFixedPitch()) {
                QTextCursor c(doc);
                c.setPosition(frag.position());
                c.setPosition(frag.position() + frag.length(), QTextCursor::KeepAnchor);
                QTextCharFormat f;
                f.setFontFamilies({ monoFont });
                f.setFontPointSize(basePt * 0.92);
                f.setBackground(inlineCodeBg);
                c.mergeCharFormat(f);
            }
        }
    }

    // 4) 表
    styleTablesRecursive(doc, doc->rootFrame(), border, codeBg, fg, basePt, bodyFont);

    // 5) 画像がはみ出さないように幅を合わせる
    const qreal avail = edit->property("width").toReal();
    if (avail > 40) {
        for (QTextBlock b = doc->begin(); b.isValid(); b = b.next()) {
            for (auto it = b.begin(); !it.atEnd(); ++it) {
                const QTextFragment frag = it.fragment();
                if (!frag.isValid() || !frag.charFormat().isImageFormat())
                    continue;
                QTextImageFormat img = frag.charFormat().toImageFormat();
                if (img.width() > avail - 16) {
                    QTextCursor c(doc);
                    c.setPosition(frag.position());
                    c.setPosition(frag.position() + frag.length(), QTextCursor::KeepAnchor);
                    img.setWidth(avail - 16);
                    c.setCharFormat(img);
                }
            }
        }
    }
}

App::~App() = default;

QString App::fileNameOf(const QUrl &url) const
{
    return QFileInfo(url.toLocalFile()).fileName();
}

QString App::pathOf(const QUrl &url) const
{
    return url.toLocalFile();
}

QString App::socketName()
{
    QString user = qEnvironmentVariable("USER");
    if (user.isEmpty())
        user = qEnvironmentVariable("USERNAME"); // Windows
    if (user.isEmpty())
        user = QStringLiteral("default");
    return QStringLiteral("yohaku-%1").arg(QString::number(qHash(user), 16));
}

bool App::sendToExisting(const QStringList &paths)
{
    QLocalSocket socket;
    socket.connectToServer(socketName());
    if (!socket.waitForConnected(300))
        return false; // 既存インスタンス無し（ソケットが残っていても繋がらなければ false）
    const QByteArray payload = paths.join(QLatin1Char('\n')).toUtf8();
    socket.write(payload);
    socket.flush();
    socket.waitForBytesWritten(300);
    socket.disconnectFromServer();
    return true;
}

void App::startListener()
{
    QLocalServer::removeServer(socketName());
    auto *server = new QLocalServer(this);
    if (!server->listen(socketName()))
        return;
    connect(server, &QLocalServer::newConnection, this, [this, server]() {
        auto *socket = server->nextPendingConnection();
        if (!socket)
            return;
        connect(socket, &QLocalSocket::readyRead, this, [this, socket]() {
            const QString data = QString::fromUtf8(socket->readAll());
            QStringList paths;
            for (const QString &line : data.split(QLatin1Char('\n'), Qt::SkipEmptyParts))
                paths.append(line);
            if (!paths.isEmpty())
                emit openPathsRequested(paths);
        });
        connect(socket, &QLocalSocket::disconnected, socket, &QLocalSocket::deleteLater);
    });
}

bool App::handleArgs(const QStringList &paths, bool forceNew)
{
    Q_UNUSED(forceNew);
    if (!paths.isEmpty()) {
        if (sendToExisting(paths))
            return false; // 既存インスタンスへ送って終了
        for (const QString &p : paths)
            m_docs->openPath(p);
        // 指定ファイルがどれも開けなかったときは空タブを出す
        if (m_docs->count() == 0)
            m_docs->addUntitled();
    } else {
        // 起動時は常に新しいタブで開始する（前回のタブは復元しない）
        m_docs->addUntitled();
    }
    startListener();
    return true;
}

void App::saveSession()
{
    // 設定と栞だけ保存する（タブの復元はしない）
    m_bookmarks->save();
    m_settings->save();
}

// ---------------------------------------------------------------------------
// Bookmarks::files の型を QML で扱いやすくする
// ---------------------------------------------------------------------------
