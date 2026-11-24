# ------------------------------------------------------------------
# File: src/makefiles/dynamichooks/dynamichooks.cmake
# Purpose: Builds DynamicHooks (function hooking) from
#    https://github.com/pet0ruk/DynamicHooks, pinned below by commit and
#    the sha256 of GitHub's archive of it, with that repository's own
#    CMake (the DynamicHooks target, unoptimised). It fetches the AsmJit
#    it generates its trampolines with, pinned in its cmake/asmjit.cmake,
#    as a static library (asmjit::asmjit).
#
#    Both are built with the compiler flags set so far (-m32 etc. on
#    Linux) and, on Windows, the static C runtime, as core is.
#
#    Overrides (cmake -D...): SP_DYNAMICHOOKS_SOURCE_DIR (a local
#    checkout; see makefiles/fetch.cmake), FETCHCONTENT_SOURCE_DIR_ASMJIT.
# ------------------------------------------------------------------
include("makefiles/fetch.cmake")

Set(SP_DYNAMICHOOKS_URL    https://github.com/pet0ruk/DynamicHooks)
Set(SP_DYNAMICHOOKS_COMMIT 11adbba5e1b4619e1ca082f303ec76ea14e86a82)
Set(SP_DYNAMICHOOKS_SHA256 5ee2bc4118746e96abc97c46949c61ce4d846fbf9274fcc6240d031208688d4e)

SP_Fetch_Source(dynamichooks
    ${SP_DYNAMICHOOKS_URL}/archive/${SP_DYNAMICHOOKS_COMMIT}.tar.gz ${SP_DYNAMICHOOKS_SHA256})

Set(DYNAMICHOOKS_TESTS OFF CACHE BOOL "" FORCE)
Add_Subdirectory(${dynamichooks_SOURCE_DIR} ${CMAKE_BINARY_DIR}/_deps/dynamichooks-build EXCLUDE_FROM_ALL)

ForEach(_target asmjit DynamicHooks)
    Set_Target_Properties(${_target} PROPERTIES POSITION_INDEPENDENT_CODE ON)
    If(MSVC)
        Set_Target_Properties(${_target} PROPERTIES
            MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    EndIf()
EndForEach()
