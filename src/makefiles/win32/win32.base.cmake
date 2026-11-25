# ------------------------------------------------------------------
# File: src/makefiles/win32/win32.base.cmake
# Purpose: This is the base Win32 CMake file which sets a bunch of
#    shared flags across all Win32 builds.
# ------------------------------------------------------------------

# ------------------------------------------------------------------
# Included makefiles
# ------------------------------------------------------------------
include("makefiles/branch/${BRANCH}.cmake")
include("makefiles/shared.cmake")

# ------------------------------------------------------------------
# Python runtime (headers, python3X.lib, Boost.Python)
# ------------------------------------------------------------------
include("makefiles/python-runtime.cmake")

# dyncall_s and dynload_s, built from thirdparty/dyncall.
include("makefiles/dyncall/dyncall.cmake")

# The loader loads Python3/plat-win/<this>.
Add_Compile_Definitions(SP_LIBPYTHON_WIN32="${PYTHONSDK_LIBPYTHON}")

# ------------------------------------------------------------------
# Add in the python sdk as an include directory.
# ------------------------------------------------------------------
Include_Directories(
    ${PYTHONSDK_INCLUDE}
)

# ------------------------------------------------------------------
# Required to get SP to compile on MSVC for csgo.
# ------------------------------------------------------------------
If(SP_X86_64)
    Add_Definitions(-DCOMPILER_MSVC -DCOMPILER_MSVC64 -D_WIN32)
Else()
    Add_Definitions(-DCOMPILER_MSVC -DCOMPILER_MSVC32 -D_WIN32)
EndIf()

# ------------------------------------------------------------------
# Release flags: optimised, without assert() (NDEBUG), like the Linux
# build's (CMake's -O3 -DNDEBUG). _NDEBUG, which these flags always had,
# is kept (Source.Python itself doesn't check it). The C runtime (static,
# /MT) is chosen by the targets' MSVC_RUNTIME_LIBRARY below, not here.
# ------------------------------------------------------------------
Set(CMAKE_CXX_FLAGS_RELEASE "/O2 /Ob2 /DNDEBUG /D_NDEBUG /wd4005 /MP")

# ------------------------------------------------------------------
# Statically link runtime libraries for the loader
# ------------------------------------------------------------------
set_property(TARGET core source-python PROPERTY
  MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

#Set_Target_Properties(core PROPERTIES
#    LINK_FLAGS_RELEASE "/NODEFAULTLIB:LIBC.lib /NODEFAULTLIB:LIBCMT.lib /NODEFAULTLIB:LIBCPMT.lib"
#)

If(NOT SP_X86_64)
    # (x64 has no SAFESEH)
    SET(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} /SAFESEH:NO")
EndIf()

# The loader uses std::filesystem (updater.cpp), which MSVC only has from C++17; its default is
# C++14 (Linux builds everything as C++17, linux.base.cmake).
Set_Target_Properties(source-python PROPERTIES CXX_STANDARD 17 CXX_STANDARD_REQUIRED ON)

# ------------------------------------------------------------------
# DynamicHooks and AsmJit, built from pinned source.
# ------------------------------------------------------------------
include("makefiles/dynamichooks/dynamichooks.cmake")

# ------------------------------------------------------------------
# Link libraries.
# ------------------------------------------------------------------
Set(SOURCEPYTHON_LINK_LIBRARIES
    ${SOURCEPYTHON_LINK_LIBRARIES}
    dyncall_s
    dynload_s
    DynamicHooks
)

If( SOURCE_ENGINE MATCHES "orangebox")
    If(SP_X86_64)
        Set(_sdk_libs ${SOURCESDK_LIB}/public/x64)
    Else()
        Set(_sdk_libs ${SOURCESDK_LIB}/public/x86)
    EndIf()
    Set(SOURCEPYTHON_LINK_LIBRARIES
        ${SOURCEPYTHON_LINK_LIBRARIES}
        ${_sdk_libs}/tier0.lib
        ${_sdk_libs}/tier1.lib
        ${_sdk_libs}/vstdlib.lib
        ${_sdk_libs}/mathlib.lib
    )
Else()
    Set(SOURCEPYTHON_LINK_LIBRARIES
        ${SOURCEPYTHON_LINK_LIBRARIES}
        ${SOURCESDK_LIB}/public/tier0.lib
        ${SOURCESDK_LIB}/public/tier1.lib
        ${SOURCESDK_LIB}/public/tier2.lib
        ${SOURCESDK_LIB}/public/tier3.lib
        ${SOURCESDK_LIB}/public/vstdlib.lib
        ${SOURCESDK_LIB}/public/mathlib.lib
    )
Endif()

# CSGO Engine adds in interfaces.lib
If( SOURCE_ENGINE MATCHES "csgo" OR SOURCE_ENGINE MATCHES "blade")
    Set(SOURCEPYTHON_LINK_LIBRARIES
        ${SOURCEPYTHON_LINK_LIBRARIES}
        ${SOURCESDK_LIB}/public/interfaces.lib
    )
Endif()

If( SOURCE_ENGINE MATCHES "csgo" OR SOURCE_ENGINE MATCHES "blade")
    Set(SOURCEPYTHON_LINK_LIBRARIES
        ${SOURCEPYTHON_LINK_LIBRARIES}
        ${SOURCESDK_LIB}/win32/release/vs2017/libprotobuf.lib
    )
Endif()

# ------------------------------------------------------------------
# Release link libraries
# ------------------------------------------------------------------
Set(SOURCEPYTHON_LINK_LIBRARIES_RELEASE)
ForEach(_lib ${PYTHONSDK_LIBS})
    List(APPEND SOURCEPYTHON_LINK_LIBRARIES_RELEASE optimized ${_lib})
EndForEach()

If( SOURCE_ENGINE MATCHES "csgo" )
    SET(SOURCEPYTHON_LINK_LIBRARIES_RELEASE
        ${SOURCEPYTHON_LINK_LIBRARIES_RELEASE}
        optimized ${SOURCESDK_LIB}/win32/release/vs2010/libprotobuf.lib
    )
Endif()
