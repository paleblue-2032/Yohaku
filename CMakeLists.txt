cmake_minimum_required(VERSION 3.21)

project(shiori VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick QuickControls2)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(shiori
    src/main.cpp
    src/backend.cpp
    src/backend.h
)

target_compile_definitions(shiori PRIVATE SHIORI_VERSION="${PROJECT_VERSION}")

# QML をリソースに同梱（engine.load("qrc:/qml/Main.qml") で読む）
qt_add_resources(shiori "shiori_qml"
    PREFIX "/"
    FILES
        qml/Main.qml
        qml/IconCross.qml
        qml/IconPlus.qml
)

target_link_libraries(shiori PRIVATE
    Qt6::Quick
    Qt6::QuickControls2
)

include(GNUInstallDirs)
install(TARGETS shiori
    BUNDLE DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
install(FILES assets/shiori.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES assets/shiori.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)
