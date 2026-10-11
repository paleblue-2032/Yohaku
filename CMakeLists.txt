cmake_minimum_required(VERSION 3.21)

project(yohaku VERSION 0.1.9 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick QuickControls2)

# Linux では標準のファイル選択 (xdg-desktop-portal) を使うため DBus を使う。
# macOS は Qt6DBus が AGL フレームワークを要求してリンクに失敗するので外す。
if(UNIX AND NOT APPLE)
    find_package(Qt6 REQUIRED COMPONENTS DBus)
endif()

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(yohaku
    src/main.cpp
    src/backend.cpp
    src/backend.h
)

target_compile_definitions(yohaku PRIVATE YOHAKU_VERSION="${PROJECT_VERSION}")

# アプリのアイコン（ウィンドウ/タスクバー用に PNG を埋め込む）
qt_add_resources(yohaku "yohaku_icon"
    PREFIX "/"
    FILES assets/yohaku.png
)

# QML をリソースに同梱（engine.load("qrc:/qml/Main.qml") で読む）
qt_add_resources(yohaku "yohaku_qml"
    PREFIX "/"
    FILES
        qml/Main.qml
        qml/IconCross.qml
        qml/IconPlus.qml
        qml/FlatButton.qml
        qml/AppMenu.qml
)

target_link_libraries(yohaku PRIVATE
    Qt6::Quick
    Qt6::QuickControls2
)

if(UNIX AND NOT APPLE)
    target_link_libraries(yohaku PRIVATE Qt6::DBus)
endif()

# Windows では GUI アプリとして（コンソールを出さない）
if(WIN32)
    set_target_properties(yohaku PROPERTIES WIN32_EXECUTABLE TRUE)
    # exe のアイコン（rc の相対パスは CWD 依存なので絶対パスで生成する）
    # rc のパスは \ が CMake のエスケープとして解釈されるため、
    # スラッシュ区切りのパス（rc も Windows API も解釈できる）を使う
    file(TO_CMAKE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/assets/yohaku.ico" _yohaku_ico)
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/yohaku_icon.rc"
         "IDI_ICON1 ICON DISCARDABLE \"${_yohaku_ico}\"\n")
    target_sources(yohaku PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/yohaku_icon.rc")
endif()

# macOS では .app バンドルとして作る（macdeployqt での配布用パッケージに必要）
if(APPLE)
    set_target_properties(yohaku PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_ICON_FILE yohaku.icns
    )
    set_source_files_properties(assets/yohaku.icns PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
    target_sources(yohaku PRIVATE assets/yohaku.icns)
endif()

include(GNUInstallDirs)
install(TARGETS yohaku
    BUNDLE DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# .desktop / アイコンは Linux・BSD 系でのみ意味がある
if(UNIX AND NOT APPLE)
    install(FILES assets/yohaku.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
    install(DIRECTORY assets/icons/hicolor DESTINATION ${CMAKE_INSTALL_DATADIR}/icons)
endif()
