#include "backend.h"

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
           + QStringLiteral("/shiori");
}

QString stateDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation)
           + QStringLiteral("/shiori");
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
    emit languageChanged();
    emit darkChanged();
    emit accentChanged();
    emit fontSizeChanged();
    emit wrapChanged();
    emit lineNumbersChanged();
}

void Settings::save() const
{
    QJsonObject o;
    o.insert(QStringLiteral("language"), m_language);
    o.insert(QStringLiteral("dark"), m_dark);
    o.insert(QStringLiteral("accent"), m_accent);
    o.insert(QStringLiteral("fontSize"), m_fontSize);
    o.insert(QStringLiteral("wrap"), m_wrap);
    o.insert(QStringLiteral("lineNumbers"), m_lineNumbers);
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
    add(m_en, "theme", "Theme");
    add(m_en, "dark", "Dark");
    add(m_en, "light", "Light");
    add(m_en, "accent", "Accent Color");
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
    add(m_ja, "theme", "テーマ");
    add(m_ja, "dark", "ダーク");
    add(m_ja, "light", "ライト");
    add(m_ja, "accent", "アクセントカラー");
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

QString DocumentModel::draftsDir()
{
    return stateDir() + QStringLiteral("/drafts");
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

QString DocumentModel::keyOf(const Doc &doc) const
{
    if (!doc.path.isEmpty())
        return doc.path;
    return doc.draftId;
}

QString DocumentModel::draftKeyOf(const Doc &doc) const
{
    if (!doc.path.isEmpty())
        return QStringLiteral("path-%1").arg(QString::number(qHash(doc.path), 16));
    return doc.draftId;
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

int DocumentModel::addFromDraft(const QString &draftId, const QString &text)
{
    Doc d;
    d.draftId = draftId;
    d.text = text;
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
    QFile::remove(draftsDir() + QLatin1Char('/') + draftKeyOf(m_docs[row]) + QStringLiteral(".txt"));
    m_docs[row].modified = false;
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

    const QString oldDraft = draftKeyOf(m_docs[row]);
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly))
        return false;
    f.write(m_docs[row].text.toUtf8());
    if (!f.commit())
        return false;

    QFile::remove(draftsDir() + QLatin1Char('/') + oldDraft + QStringLiteral(".txt"));
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
    if (m_docs[row].modified || m_docs[row].path.isEmpty())
        QFile::remove(draftsDir() + QLatin1Char('/') + draftKeyOf(m_docs[row])
                      + QStringLiteral(".txt"));
    beginRemoveRows(QModelIndex(), row, row);
    m_docs.remove(row);
    endRemoveRows();
    emit countChanged();
}

QJsonArray DocumentModel::sessionTabs() const
{
    QJsonArray arr;
    for (const Doc &d : m_docs) {
        if (d.path.isEmpty() && d.text.isEmpty() && !d.modified)
            continue; // 空の無題タブは残さない
        QJsonObject o;
        o.insert(QStringLiteral("path"), d.path);
        o.insert(QStringLiteral("draftId"), d.draftId);
        arr.append(o);
    }
    return arr;
}

void DocumentModel::writeDrafts(bool enabled) const
{
    QDir().mkpath(draftsDir());
    for (const Doc &d : m_docs) {
        const QString path =
            draftsDir() + QLatin1Char('/') + draftKeyOf(d) + QStringLiteral(".txt");
        if (!enabled) {
            QFile::remove(path);
            continue;
        }
        if (d.modified || d.path.isEmpty()) {
            QSaveFile f(path);
            if (f.open(QIODevice::WriteOnly)) {
                f.write(d.text.toUtf8());
                f.commit();
            }
        } else {
            QFile::remove(path);
        }
    }
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

App::App(DocumentModel *docs, Settings *settings, Bookmarks *bookmarks, QObject *parent)
    : QObject(parent), m_docs(docs), m_settings(settings), m_bookmarks(bookmarks)
{
    // プラットフォームごとに日本語が出せる UI フォントを選ぶ
    const QStringList candidates = {
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
    return QStringLiteral("shiori-%1").arg(QString::number(qHash(user), 16));
}

bool App::sendToExisting(const QStringList &paths)
{
    QLocalSocket socket;
    socket.connectToServer(socketName());
    if (!socket.waitForConnected(300)) {
        // 接続できない理由が「サーバー無し」かどうかを確認
        if (socket.error() == QLocalSocket::ConnectionRefusedError
            || socket.error() == QLocalSocket::ServerNotFoundError)
            return false;
    }
    if (socket.state() != QLocalSocket::ConnectedState)
        return false;
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
    if (!paths.isEmpty()) {
        if (sendToExisting(paths))
            return false; // 既存インスタンスへ送って終了
        for (const QString &p : paths)
            m_docs->openPath(p);
    } else {
        if (!forceNew)
            restoreSession();
        m_docs->addUntitled();
    }
    startListener();
    return true;
}

void App::restoreDraftsAt(int row)
{
    // パス付き文書の未保存ドラフトがあれば復元する
    const QString path = m_docs->pathAt(row);
    if (path.isEmpty())
        return;
    const QString key = QStringLiteral("path-%1").arg(QString::number(qHash(path), 16));
    QFile f(DocumentModel::draftsDir() + QLatin1Char('/') + key + QStringLiteral(".txt"));
    if (!f.open(QIODevice::ReadOnly))
        return;
    const QString text = QString::fromUtf8(f.readAll());
    if (!text.isEmpty() && text != m_docs->textAt(row))
        m_docs->setTextAt(row, text);
}

void App::restoreSession()
{
    const QJsonObject o = readJson(stateDir() + QStringLiteral("/session.json"));
    for (const QJsonValue &v : o.value(QStringLiteral("tabs")).toArray()) {
        const QJsonObject t = v.toObject();
        const QString path = t.value(QStringLiteral("path")).toString();
        if (!path.isEmpty()) {
            const int row = m_docs->openPath(path);
            if (row >= 0)
                restoreDraftsAt(row);
            continue;
        }
        const QString draftId = t.value(QStringLiteral("draftId")).toString();
        if (draftId.isEmpty())
            continue;
        QFile f(DocumentModel::draftsDir() + QLatin1Char('/') + draftId + QStringLiteral(".txt"));
        QString text;
        if (f.open(QIODevice::ReadOnly))
            text = QString::fromUtf8(f.readAll());
        m_docs->addFromDraft(draftId, text);
    }
}

void App::saveSession()
{
    m_docs->writeDrafts(true);

    QJsonObject o;
    o.insert(QStringLiteral("tabs"), m_docs->sessionTabs());
    writeJson(stateDir() + QStringLiteral("/session.json"), o);

    m_bookmarks->save();
    m_settings->save();
}

// ---------------------------------------------------------------------------
// Bookmarks::files の型を QML で扱いやすくする
// ---------------------------------------------------------------------------
