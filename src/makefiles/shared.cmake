# ------------------------------------------------------------------
# File: src/makefiles/shared.cmake
# Purpose: This is the base Win32 CMake file which sets a bunch of
#    shared flags across all Win32 builds.
# ------------------------------------------------------------------

# ------------------------------------------------------------------
# We only need a release and debug configuration.
# ------------------------------------------------------------------
Set(CMAKE_CONFIGURATION_TYPES "Debug;Release" CACHE STRING 
	"Only do Release and Debug" 
	FORCE
)

# ------------------------------------------------------------------
# Architecture: x86 (32-bit, every game) or x86_64 (the games with
# 64-bit dedicated servers, whose SDK branch has 64-bit libraries).
# On Windows it must match the generator platform (-A Win32 / -A x64).
# ------------------------------------------------------------------
Set(SP_ARCH x86 CACHE STRING "Architecture to build for: x86 or x86_64")
Set_Property(CACHE SP_ARCH PROPERTY STRINGS x86 x86_64)
Set(SP_X86_64_BRANCHES tf2 css dods hl2dm)
If(SP_ARCH STREQUAL "x86_64")
    If(NOT BRANCH IN_LIST SP_X86_64_BRANCHES)
        Message(FATAL_ERROR "SP_ARCH=x86_64: ${BRANCH} has no 64-bit server (64-bit builds: ${SP_X86_64_BRANCHES})")
    EndIf()
    If(WIN32)
        # Not yet: the Windows build still links the SDK's 32-bit libraries, and Source.Python
        # keeps addresses in unsigned long, which is 32 bits on 64-bit Windows.
        Message(FATAL_ERROR "SP_ARCH=x86_64 is only supported on Linux so far")
    EndIf()
    Set(SP_X86_64 TRUE)
    # The SDK's 64-bit build (platform.h, ...)
    Add_Definitions(-DX64BITS -DPLATFORM_64BITS)
ElseIf(SP_ARCH STREQUAL "x86")
    Set(SP_X86_64 FALSE)
Else()
    Message(FATAL_ERROR "SP_ARCH must be x86 or x86_64, not ${SP_ARCH}")
EndIf()

# ------------------------------------------------------------------
# Setup include paths.
# ------------------------------------------------------------------
Set(SOURCESDK_DIR        ${CMAKE_CURRENT_SOURCE_DIR}/hl2sdk)
Set(THIRDPARTY_DIR       ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty)

# ------------------------------------------------------------------
# SDK Directories.
# ------------------------------------------------------------------
Set(SOURCESDK            ${SOURCESDK_DIR}/${BRANCH})
Set(SOURCESDK_LIB        ${SOURCESDK}/lib)

# ------------------------------------------------------------------
# Dyncall specific.
# ------------------------------------------------------------------
# Built from source by makefiles/dyncall/dyncall.cmake.
Set(DYNCALLSDK           ${THIRDPARTY_DIR}/dyncall)
Set(DYNCALLSDK_INCLUDE   ${DYNCALLSDK}/dyncall ${DYNCALLSDK}/dynload)

# ------------------------------------------------------------------
# Include directories
# ------------------------------------------------------------------
Include_Directories(
    ${SOURCESDK}
    ${SOURCESDK}/common
    ${SOURCESDK}/common/protobuf-2.5.0/src
    ${SOURCESDK}/game/shared
    ${SOURCESDK}/game/server
    ${SOURCESDK}/public
    ${SOURCESDK}/public/tier0
    ${SOURCESDK}/public/tier1
    ${SOURCESDK}/public/engine/protobuf
    ${DYNCALLSDK_INCLUDE}
    ${CMAKE_CURRENT_SOURCE_DIR}/core # Hack but required.
)

# ------------------------------------------------------------------
# This is required to get boost to statically link.
# ------------------------------------------------------------------
Add_Definitions(
    -DBOOST_PYTHON_STATIC_LIB
    -DBOOST_PYTHON_SOURCE
    -DBOOST_PYTHON_NO_LIB
)

# ------------------------------------------------------------------
# The project.
# ------------------------------------------------------------------
Project(source-python C CXX)