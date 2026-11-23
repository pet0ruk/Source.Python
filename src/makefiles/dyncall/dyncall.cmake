# ------------------------------------------------------------------
# File: src/makefiles/dyncall/dyncall.cmake
# Purpose: Builds dyncall_s and dynload_s from the dyncall 1.4 source
#    in thirdparty/dyncall (see its README.md), with the same
#    compiler and runtime settings as core and the loader.
#
#    The sources are the ones dyncall's own CMakeLists.txt files
#    list; the call kernel is assembly (GNU as on Linux, MASM with
#    MSVC). Architecture-specific C files are #included by these.
# ------------------------------------------------------------------
Set(DYNCALL_SRC ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/dyncall)

If(MSVC)
    Enable_Language(ASM_MASM)
    Set(DYNCALL_KERNEL ${DYNCALL_SRC}/dyncall/dyncall_call_x86_generic_masm.asm)
Else()
    Enable_Language(ASM)
    Set(DYNCALL_KERNEL ${DYNCALL_SRC}/dyncall/dyncall_call.S)
EndIf()

Add_Library(dyncall_s STATIC
    ${DYNCALL_KERNEL}
    ${DYNCALL_SRC}/dyncall/dyncall_vector.c
    ${DYNCALL_SRC}/dyncall/dyncall_aggregate.c
    ${DYNCALL_SRC}/dyncall/dyncall_api.c
    ${DYNCALL_SRC}/dyncall/dyncall_callvm.c
    ${DYNCALL_SRC}/dyncall/dyncall_callvm_base.c
    ${DYNCALL_SRC}/dyncall/dyncall_callf.c
)

Add_Library(dynload_s STATIC
    ${DYNCALL_SRC}/dynload/dynload.c
    ${DYNCALL_SRC}/dynload/dynload_syms.c
)

ForEach(_target dyncall_s dynload_s)
    Set_Target_Properties(${_target} PROPERTIES POSITION_INDEPENDENT_CODE ON)
    If(MSVC)
        # The static C runtime, as core and the loader (win32.base.cmake).
        Set_Target_Properties(${_target} PROPERTIES
            MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    Else()
        Target_Compile_Options(${_target} PRIVATE
            -m32
            # dyncall's assembly has no .note.GNU-stack section; without this
            # its objects would make core.so require an executable stack.
            $<$<COMPILE_LANGUAGE:ASM>:-Wa,--noexecstack>
        )
    EndIf()
EndForEach()
