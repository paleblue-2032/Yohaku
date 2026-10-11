#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QTextStream>
#include <QTimer>

#include <cstdio>
#include <cstdlib>

#include "backend.h"

#ifndef YOHAKU_VERSION
#define YOHAKU_VERSION "0.0.0"
#endif

namespace {

// Linux では xdg-desktop-portal のファイル選択（Nautilus 等、その環境の標準アプリ）を
// 使いたい。Qt の xdgdesktopportal プラットフォームテーマ経由で標準ダイアログになるので、
// ポータルが利用できるときだけ自動で設定する。
bool portalFileDialogAvailable()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return false;
    QDBusConnectionInterface *iface = bus.interface();
    return iface && iface->isServiceRegistered(QStringLiteral("org.freedesktop.portal.Desktop")).value();
}

} // namespace

int main(int argc, char *argv[])
{
#if defined(Q_OS_LINUX)
    if (qEnvironmentVariableIsEmpty("QT_QPA_PLATFORMTHEME") && portalFileDialogAvailable())
        qputenv("QT_QPA_PLATFORMTHEME", "xdgdesktopportal");
#endif

    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("yohaku"));
    app.setApplicationDisplayName(QStringLiteral("Yohaku"));
    app.setOrganizationName(QStringLiteral("paleblue"));
    app.setOrganizationDomain(QStringLiteral("dev.paleblue"));
    app.setDesktopFileName(QStringLiteral("yohaku"));

    // 同梱 QML のディスクキャッシュはビルド間でキーが衝突し、更新後に古い UI が
    // 使われることがある。キャッシュ自体は起動を速くするので、ビルドごとに
    // 別ディレクトリへ分けて有効にしておく。
    const QString cacheRoot = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    if (!cacheRoot.isEmpty()) {
        const QString buildId =
            QString::number(qHash(QCoreApplication::applicationFilePath()), 16);
        qputenv("QML_DISK_CACHE_PATH",
                (cacheRoot + QStringLiteral("/qmlcache-") + buildId).toUtf8());
    }

    // ネイティブスタイルではなく Basic を土台にして QML で見た目を作り込む。
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    Settings settings;
    settings.load();
    I18n i18n(&settings);
    Bookmarks bookmarks;
    bookmarks.load();
    DocumentModel docs(&bookmarks);
    App backend(&docs, &settings, &bookmarks);

    // CLI 引数
    QStringList files;
    bool forceNew = false;
    QString initialQuery;
    const QStringList args = app.arguments().mid(1);
    for (int i = 0; i < args.size(); ++i) {
        const QString a = args.at(i);
        if (a == QLatin1String("-h") || a == QLatin1String("--help")) {
            QTextStream(stdout)
                << "Yohaku " YOHAKU_VERSION " — a simple notepad editor with bookmarks\n\n"
                   "Usage:\n  yohaku [options] [files...]\n\n"
                   "Options:\n"
                   "  -n, --new        start with a new note (do not restore tabs)\n"
                   "      --preview    start in Markdown preview mode\n"
                   "      --find TEXT  open with the find bar prefilled\n"
                   "  -h, --help       show this help\n"
                   "  -V, --version    show version\n";
            return 0;
        }
        if (a == QLatin1String("-V") || a == QLatin1String("--version")) {
            QTextStream(stdout) << "Yohaku " YOHAKU_VERSION "\n";
            return 0;
        }
        if (a == QLatin1String("-n") || a == QLatin1String("--new")) {
            forceNew = true;
        } else if (a == QLatin1String("--preview")) {
            backend.setStartInPreview(true);
        } else if (a == QLatin1String("--find") && i + 1 < args.size()) {
            initialQuery = args.at(++i);
        } else if (!a.startsWith(QLatin1Char('-'))) {
            files << a;
        }
    }
    backend.setInitialQuery(initialQuery);

    // 既存インスタンスがあればファイルを送って終了する。
    if (!backend.handleArgs(files, forceNew))
        return 0;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("Settings"), &settings);
    engine.rootContext()->setContextProperty(QStringLiteral("I18n"), &i18n);
    engine.rootContext()->setContextProperty(QStringLiteral("Bookmarks"), &bookmarks);
    engine.rootContext()->setContextProperty(QStringLiteral("Docs"), &docs);
    engine.rootContext()->setContextProperty(QStringLiteral("App"), &backend);

    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);

    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    if (engine.rootObjects().isEmpty())
        return -1;

    // ウィンドウをアクティブにして、起動直後からキーボード入力を受け付ける
    if (auto *w = qobject_cast<QQuickWindow *>(engine.rootObjects().first())) {
        w->requestActivate();
        w->raise();
    }
    QObject::connect(&backend, &App::openPathsRequested, &app, [&](const QStringList &paths) {
        for (const QString &p : paths)
            docs.openPath(p);
        if (!engine.rootObjects().isEmpty()) {
            if (auto *w = qobject_cast<QQuickWindow *>(engine.rootObjects().first())) {
                w->requestActivate();
                w->raise();
            }
        }
    });

    QObject::connect(&app, &QCoreApplication::aboutToQuit, &backend, &App::saveSession);

    // 開発用: YOHAKU_SCREENSHOT=<path> でウィンドウを撮って終了する。
    // 遅延は YOHAKU_SCREENSHOT_DELAY_MS で変更できる（既定 1000ms）。
    const QByteArray shot = qgetenv("YOHAKU_SCREENSHOT");
    if (!shot.isEmpty()) {
        int delay = qEnvironmentVariableIntValue("YOHAKU_SCREENSHOT_DELAY_MS");
        if (delay <= 0)
            delay = 1000;
        QTimer::singleShot(delay, &app, [&]() {
            if (!engine.rootObjects().isEmpty()) {
                if (auto *w = qobject_cast<QQuickWindow *>(engine.rootObjects().first()))
                    w->grabWindow().save(QString::fromUtf8(shot));
            }
            // 開発用の撮影なので、終了確認などに引っかからず即座に終わる
            std::fflush(nullptr);
            std::_Exit(0);
        });
    }

    return app.exec();
}
