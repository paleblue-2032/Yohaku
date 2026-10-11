cmake_minimum_required(VERSION 3.21)

project(yohaku VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick QuickControls2 DBus)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(yohaku
    src/main.cpp
    src/backend.cpp
    src/backend.h
)

target_compile_definitions(yohaku PRIVATE YOHAKU_VERSION="${PROJECT_VERSION}")

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
    Qt6::DBus
)

# Windows では GUI アプリとして（コンソールを出さない）
if(WIN32)
    set_target_properties(yohaku PROPERTIES WIN32_EXECUTABLE TRUE)
endif()

include(GNUInstallDirs)
install(TARGETS yohaku
    BUNDLE DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# .desktop / アイコンは Linux・BSD 系でのみ意味がある
if(UNIX AND NOT APPLE)
    install(FILES assets/yohaku.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
    install(FILES assets/yohaku.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)
endif()
