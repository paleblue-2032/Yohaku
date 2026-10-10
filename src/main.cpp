#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTextStream>
#include <QTimer>

#include "backend.h"

#ifndef SHIORI_VERSION
#define SHIORI_VERSION "0.0.0"
#endif

int main(int argc, char *argv[])
{
    // 同梱 QML のディスクキャッシュはビルド間でキーが衝突し、
    // 更新後に古い UI が使われることがあるため無効化する。
    qputenv("QML_DISABLE_DISK_CACHE", "1");

    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("shiori"));
    app.setApplicationDisplayName(QStringLiteral("shiori"));
    app.setOrganizationName(QStringLiteral("paleblue"));
    app.setOrganizationDomain(QStringLiteral("dev.paleblue"));
    app.setDesktopFileName(QStringLiteral("shiori"));

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
                << "shiori " SHIORI_VERSION " — a simple notepad editor with bookmarks\n\n"
                   "Usage:\n  shiori [options] [files...]\n\n"
                   "Options:\n"
                   "  -n, --new        start with a new note (do not restore tabs)\n"
                   "      --preview    start in Markdown preview mode\n"
                   "      --find TEXT  open with the find bar prefilled\n"
                   "  -h, --help       show this help\n"
                   "  -V, --version    show version\n";
            return 0;
        }
        if (a == QLatin1String("-V") || a == QLatin1String("--version")) {
            QTextStream(stdout) << "shiori " SHIORI_VERSION "\n";
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

    // 開発用: SHIORI_SCREENSHOT=<path> でウィンドウを撮って終了する。
    const QByteArray shot = qgetenv("SHIORI_SCREENSHOT");
    if (!shot.isEmpty()) {
        QTimer::singleShot(1000, &app, [&]() {
            if (!engine.rootObjects().isEmpty()) {
                if (auto *w = qobject_cast<QQuickWindow *>(engine.rootObjects().first()))
                    w->grabWindow().save(QString::fromUtf8(shot));
            }
            QCoreApplication::quit();
        });
    }

    return app.exec();
}
