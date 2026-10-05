CMAKE_MINIMUM_REQUIRED(VERSION 3.10)

PROJECT(AETHYRA)

SET(VERSION 0.0.29.1)

# World hosting (eathena/worldhost.cpp) uses std::filesystem.
SET(CMAKE_CXX_STANDARD 17)
SET(CMAKE_CXX_STANDARD_REQUIRED ON)

# where to look for cmake modules
SET(CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/CMake/Modules)

FIND_PACKAGE(Gettext)

OPTION(WITH_OPENGL "Enable OpenGL support" ON)
OPTION(ENABLE_NLS "Enable building of translations" ON)

IF (WIN32)
    SET(PKG_DATADIR ".")
    SET(PKG_BINDIR ".")
    SET(LOCALEDIR ".")
ELSE (WIN32)
    IF (NOT OSX)
        OPTION(USE_X11 "Use X11 Clipboard functionality" ON)
    ENDIF ()
    SET(PKG_DATADIR ${CMAKE_INSTALL_PREFIX}/share/aethyra)
    SET(LOCALEDIR ${CMAKE_INSTALL_PREFIX}/share/locale)
    SET(PKG_BINDIR ${CMAKE_INSTALL_PREFIX}/bin)
ENDIF (WIN32)

ADD_SUBDIRECTORY(data)
ADD_SUBDIRECTORY(src)

IF (GETTEXT_FOUND AND ENABLE_NLS)
    ADD_SUBDIRECTORY(po)
ENDIF()

INSTALL(FILES aethyra.desktop DESTINATION share/applications)
