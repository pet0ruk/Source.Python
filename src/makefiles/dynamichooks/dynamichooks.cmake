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
Set(SP_DYNAMICHOOKS_COMMIT 60a107547ae4a7c3c4e9c9e4f48b14113c015343)
Set(SP_DYNAMICHOOKS_SHA256 9f0a7ac0e8a3b83faa07b841b7120dbf7eb9547e703d2b3ec46029e081ad99a6)

SP_Fetch_Source(dynamichooks
    ${SP_DYNAMICHOOKS_URL}/archive/${SP_DYNAMICHOOKS_COMMIT}.tar.gz ${SP_DYNAMICHOOKS_SHA256})

Set(DYNAMICHOOKS_TESTS OFF CACHE BOOL "" FORCE)
# x86-64 builds also fetch safetyhook (pinned in DynamicHooks' cmake/safetyhook.cmake).
Set(DYNAMICHOOKS_X86_64 ${SP_X86_64} CACHE BOOL "" FORCE)
Add_Subdirectory(${dynamichooks_SOURCE_DIR} ${CMAKE_BINARY_DIR}/_deps/dynamichooks-build EXCLUDE_FROM_ALL)

Set(_dynamichooks_targets asmjit DynamicHooks)
If(SP_X86_64)
    List(APPEND _dynamichooks_targets safetyhook)
EndIf()
ForEach(_target ${_dynamichooks_targets})
    Set_Target_Properties(${_target} PROPERTIES POSITION_INDEPENDENT_CODE ON)
    If(MSVC)
        Set_Target_Properties(${_target} PROPERTIES
            MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    EndIf()
EndForEach()
