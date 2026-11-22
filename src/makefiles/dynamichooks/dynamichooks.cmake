# ------------------------------------------------------------------
# File: src/makefiles/dynamichooks/dynamichooks.cmake
# Purpose: Builds DynamicHooks (function hooking) and the AsmJit it
#    generates its trampolines with, from source pinned below by commit
#    and the sha256 of GitHub's archive of it.
#
#    AsmJit is the commit whose headers DynamicHooks 92f9de59 ships in
#    src/thirdparty/AsmJit (91 of 92 identical; AsmJit.h is asmjit.h
#    renamed), built with AsmJit's own CMake as a static library.
#    DynamicHooks' own CMake links the prebuilt AsmJit it ships, so its
#    sources are listed here (the same ones), and like its own build it
#    is compiled without optimisation.
#
#    Overrides (cmake -D...): SP_ASMJIT_SOURCE_DIR,
#    SP_DYNAMICHOOKS_SOURCE_DIR (see makefiles/fetch.cmake).
# ------------------------------------------------------------------
include("makefiles/fetch.cmake")

Set(SP_ASMJIT_COMMIT       e8c8e2e48a1a38154c8e8864eb3bc61db80a1e31)
Set(SP_ASMJIT_SHA256       f3d0f56413dd88d069895e0f3933962cf1b687e901fb207a5b889ef5870b128a)
Set(SP_DYNAMICHOOKS_URL    https://github.com/Ayuto/DynamicHooks)
Set(SP_DYNAMICHOOKS_COMMIT 92f9de59c72be4bf4f7ba5d74e987ab12a031fd4)
Set(SP_DYNAMICHOOKS_SHA256 8159e3935a8900f6ce92985dc05706c397d55621dd0458ff1a237671fb6c8388)

SP_Fetch_Source(asmjit
    https://github.com/asmjit/asmjit/archive/${SP_ASMJIT_COMMIT}.tar.gz ${SP_ASMJIT_SHA256})
SP_Fetch_Source(dynamichooks
    ${SP_DYNAMICHOOKS_URL}/archive/${SP_DYNAMICHOOKS_COMMIT}.tar.gz ${SP_DYNAMICHOOKS_SHA256})

# ------------------------------------------------------------------
# AsmJit: a static library, otherwise its default configuration. It
# inherits the compiler flags set so far (-m32 etc. on Linux), and passes
# its build options (-DASMJIT_STATIC) on to whatever links it.
# ------------------------------------------------------------------
Set(ASMJIT_STATIC     TRUE)
Set(ASMJIT_NO_NATVIS  TRUE)
Set(ASMJIT_NO_INSTALL TRUE)
Add_Subdirectory(${asmjit_SOURCE_DIR} ${CMAKE_BINARY_DIR}/_deps/asmjit-build EXCLUDE_FROM_ALL)
Set_Target_Properties(asmjit PROPERTIES POSITION_INDEPENDENT_CODE ON)
If(MSVC)
    Set_Target_Properties(asmjit PROPERTIES
        MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
EndIf()

# ------------------------------------------------------------------
# DynamicHooks
# ------------------------------------------------------------------
Set(DYNAMICHOOKS_SRC ${dynamichooks_SOURCE_DIR}/src)

Add_Library(DynamicHooks STATIC
    ${DYNAMICHOOKS_SRC}/conventions/x86MsCdecl.cpp
    ${DYNAMICHOOKS_SRC}/conventions/x86MsThiscall.cpp
    ${DYNAMICHOOKS_SRC}/conventions/x86MsStdcall.cpp
    ${DYNAMICHOOKS_SRC}/conventions/x86MsFastcall.cpp
    ${DYNAMICHOOKS_SRC}/asm.cpp
    ${DYNAMICHOOKS_SRC}/hook.cpp
    ${DYNAMICHOOKS_SRC}/manager.cpp
    ${DYNAMICHOOKS_SRC}/registers.cpp
    ${DYNAMICHOOKS_SRC}/utilities.cpp
)
Set_Target_Properties(DynamicHooks PROPERTIES POSITION_INDEPENDENT_CODE ON)
Target_Link_Libraries(DynamicHooks PUBLIC asmjit::asmjit)
# DynamicHooks includes its headers and AsmJit's as "hook.h", "x86.h"; so
# does core, through them.
Target_Include_Directories(DynamicHooks PUBLIC
    ${DYNAMICHOOKS_SRC}
    ${asmjit_SOURCE_DIR}/src/asmjit
)
If(MSVC)
    Set_Target_Properties(DynamicHooks PROPERTIES
        MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    Target_Compile_Options(DynamicHooks PRIVATE /Od /Ob0)
Else()
    Target_Compile_Options(DynamicHooks PRIVATE -O0)
EndIf()
