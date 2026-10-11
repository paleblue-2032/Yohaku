#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QJsonArray>
#include <QFileSystemWatcher>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariantList>
#include <QVector>

// ---------------------------------------------------------------------------
// 設定（$XDG_CONFIG_HOME/yohaku/settings.json）
// ---------------------------------------------------------------------------
class Settings : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString language READ language WRITE setLanguage NOTIFY languageChanged)
    Q_PROPERTY(bool dark READ dark WRITE setDark NOTIFY darkChanged)
    Q_PROPERTY(QString accent READ accent WRITE setAccent NOTIFY accentChanged)
    Q_PROPERTY(int fontSize READ fontSize WRITE setFontSize NOTIFY fontSizeChanged)
    Q_PROPERTY(bool wrap READ wrap WRITE setWrap NOTIFY wrapChanged)
    Q_PROPERTY(bool lineNumbers READ lineNumbers WRITE setLineNumbers NOTIFY lineNumbersChanged)
    Q_PROPERTY(qreal windowOpacity READ windowOpacity WRITE setWindowOpacity NOTIFY windowOpacityChanged)
    Q_PROPERTY(QString previewFont READ previewFont WRITE setPreviewFont NOTIFY previewFontChanged)

public:
    explicit Settings(QObject *parent = nullptr);

    QString language() const { return m_language; }
    bool dark() const { return m_dark; }
    QString accent() const { return m_accent; }
    int fontSize() const { return m_fontSize; }
    bool wrap() const { return m_wrap; }
    bool lineNumbers() const { return m_lineNumbers; }
    qreal windowOpacity() const { return m_windowOpacity; }
    QString previewFont() const { return m_previewFont; }

    void setLanguage(const QString &v);
    void setDark(bool v);
    void setAccent(const QString &v);
    void setFontSize(int v);
    void setWrap(bool v);
    void setLineNumbers(bool v);
    void setWindowOpacity(qreal v);
    void setPreviewFont(const QString &v);

    void load();
    void save() const;

    static QString filePath();

signals:
    void languageChanged();
    void darkChanged();
    void accentChanged();
    void fontSizeChanged();
    void wrapChanged();
    void lineNumbersChanged();
    void windowOpacityChanged();
    void previewFontChanged();

private:
    QString m_language = QStringLiteral("en");
    bool m_dark = true;
    QString m_accent = QStringLiteral("#4cc2ff");
    int m_fontSize = 15;
    bool m_wrap = true;
    bool m_lineNumbers = true;
    qreal m_windowOpacity = 0.9;
    QString m_previewFont = QStringLiteral("sans");
};

// ---------------------------------------------------------------------------
// キー設定（$XDG_CONFIG_HOME/yohaku/keymap.json で書き換えられる）
// ---------------------------------------------------------------------------

class Keymap : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int rev READ rev NOTIFY changed)

public:
    explicit Keymap(QObject *parent = nullptr);

    int rev() const { return m_rev; }
    /// アクションに割り当てられたキー配列（未設定なら既定）
    Q_INVOKABLE QStringList seq(const QString &action) const;
    Q_INVOKABLE QString primary(const QString &action) const;

    void load();
    void watch();
    static QString filePath();

signals:
    void changed();

private:
    void writeDefault() const;
    QHash<QString, QStringList> m_map;
    int m_rev = 0;
    QFileSystemWatcher *m_watcher = nullptr;
};

// ---------------------------------------------------------------------------
// i18n（キー -> 文字列。QML からは I18n.t("file")、依存は I18n.rev で確保）
// ---------------------------------------------------------------------------
class I18n : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int rev READ rev NOTIFY changed)

public:
    explicit I18n(Settings *settings, QObject *parent = nullptr);

    int rev() const { return m_rev; }
    Q_INVOKABLE QString t(const QString &key) const;

signals:
    void changed();

private:
    Settings *m_settings;
    int m_rev = 0;
    QHash<QString, QString> m_en;
    QHash<QString, QString> m_ja;
};

// ---------------------------------------------------------------------------
// 栞（自動位置・手動行栞・ファイル栞）
// ---------------------------------------------------------------------------
class Bookmarks : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList files READ files NOTIFY changed)
    Q_PROPERTY(int rev READ rev NOTIFY changed)

public:
    explicit Bookmarks(QObject *parent = nullptr);

    QVariantList files() const { return m_files; }
    int rev() const { return m_rev; }

    Q_INVOKABLE int lastPosition(const QString &key) const;
    Q_INVOKABLE void setLastPosition(const QString &key, int line);
    Q_INVOKABLE QVariantList lineMarks(const QString &key) const;
    Q_INVOKABLE void setLineMarks(const QString &key, const QVariantList &marks);
    Q_INVOKABLE bool isFileBookmarked(const QString &key) const;
    Q_INVOKABLE bool toggleFile(const QString &key, const QString &title, const QString &path);
    Q_INVOKABLE void removeFile(const QString &key);

    void load();
    void save();

signals:
    void changed();

private:
    static QString filePath();
    int m_rev = 0;
    QHash<QString, int> m_last;
    QHash<QString, QVariantList> m_lines;
    QVariantList m_files;
};

// ---------------------------------------------------------------------------
// 文書モデル（タブ）
// ---------------------------------------------------------------------------
class DocumentModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Roles {
        TitleRole = Qt::UserRole + 1,
        TextRole,
        PathRole,
        ModifiedRole,
        KeyRole,
    };

    explicit DocumentModel(Bookmarks *bookmarks, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return m_docs.size(); }

    Q_INVOKABLE int addUntitled();
    Q_INVOKABLE int openPath(const QString &path);
    Q_INVOKABLE void setTextAt(int row, const QString &text);
    Q_INVOKABLE QString textAt(int row) const;
    Q_INVOKABLE QString titleAt(int row) const;
    Q_INVOKABLE QString keyAt(int row) const;
    Q_INVOKABLE QString pathAt(int row) const;
    Q_INVOKABLE bool saveAt(int row);
    Q_INVOKABLE bool saveAsAt(int row, const QUrl &url);
    Q_INVOKABLE void closeAt(int row);
    Q_INVOKABLE bool isModifiedAt(int row) const;
    Q_INVOKABLE bool anyModified() const;
    Q_INVOKABLE void saveAll();


signals:
    void countChanged();
    void modifiedChanged(int row);

private:
    struct Doc {
        QString title;
        QString text;
        QString path;
        QString draftId;
        bool modified = false;
    };

    int indexOfPath(const QString &path) const;
    QString keyOf(const Doc &doc) const;
    QString draftKeyOf(const Doc &doc) const;

    QVector<Doc> m_docs;
    Bookmarks *m_bookmarks;
};

// ---------------------------------------------------------------------------
// アプリ全体（CLI・セッション・単一インスタンス）
// ---------------------------------------------------------------------------
class App : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString uiFont READ uiFont CONSTANT)
    Q_PROPERTY(QString monoFont READ monoFont CONSTANT)
    Q_PROPERTY(bool startInPreview READ startInPreview CONSTANT)
    Q_PROPERTY(QString initialQuery READ initialQuery CONSTANT)

public:
    App(DocumentModel *docs, Settings *settings, Bookmarks *bookmarks, QObject *parent = nullptr);
    ~App() override;

    Q_INVOKABLE QString fileNameOf(const QUrl &url) const;
    Q_INVOKABLE QString pathOf(const QUrl &url) const;

    /// 利用可能な日本語対応 UI フォント（プラットフォームごとに選ぶ）
    QString uiFont() const { return m_uiFont; }
    QString monoFont() const { return m_monoFont; }

    bool startInPreview() const { return m_startInPreview; }
    QString initialQuery() const { return m_initialQuery; }

    void setStartInPreview(bool v) { m_startInPreview = v; }
    void setInitialQuery(const QString &q) { m_initialQuery = q; }

    /// CLI 引数を処理する。既存インスタンスへ送って終了すべき場合は false。
    bool handleArgs(const QStringList &paths, bool forceNew);

    /// Markdown を GitHub 風に整形して QML の TextEdit に流し込む
    Q_INVOKABLE void renderMarkdown(QObject *edit, const QString &text);
    /// コードブロックの範囲 [[start, end], ...]（QML 側で背景を描くため）
    Q_INVOKABLE QVariantList codeBlockRanges(QObject *edit);
    /// 見出しアンカー (#...) の文字位置を返す（無ければ -1）
    Q_INVOKABLE int findAnchor(QObject *edit, const QString &anchor);
    static QString slugifyForAnchor(const QString &text);

public slots:
    void saveSession();

signals:
    void openPathsRequested(const QStringList &paths);

private:
    static QString socketName();
    bool sendToExisting(const QStringList &paths);
    void startListener();

    DocumentModel *m_docs;
    Settings *m_settings;
    Bookmarks *m_bookmarks;
    QString m_uiFont;
    QString m_monoFont;
    bool m_startInPreview = false;
    QString m_initialQuery;
};
