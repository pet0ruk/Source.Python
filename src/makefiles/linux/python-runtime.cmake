# ------------------------------------------------------------------
# File: src/makefiles/linux/python-runtime.cmake
# Purpose: Provides the Python runtime Source.Python is built against
#    and shipped with on Linux: a bundle from
#    https://github.com/pet0ruk/source-python-runtime (CPython, the
#    compiled site-packages and Boost.Python built for that exact
#    interpreter), pinned below by release and sha256.
#
#    The bundle is downloaded and unpacked into
#    <build dir>/python-runtime:
#      build/include, build/lib  headers, libpython, Boost.Python
#      runtime/                  laid over the release tree (Python3/,
#                                compiled site-packages)
#      manifest.txt              versions (python_abi, libpython, ...)
#
#    Overrides (cmake -D...):
#      SP_PYTHON_RUNTIME_ARCHIVE  a local bundle .tar.gz to use instead
#                                 of downloading (not checksum-verified)
# ------------------------------------------------------------------
Set(SP_PYTHON_RUNTIME_RELEASE  3.13.2-r1)
Set(SP_PYTHON_RUNTIME_PLATFORM manylinux_2_28_i686)
Set(SP_PYTHON_RUNTIME_SHA256   83a32867e816aa0f4ea95f31d025630a54b5b8bf2771237b5525c569b2a1d541)
Set(SP_PYTHON_RUNTIME_URL_BASE https://github.com/pet0ruk/source-python-runtime/releases/download)

Set(SP_PYTHON_RUNTIME_NAME sp-python-${SP_PYTHON_RUNTIME_RELEASE}-${SP_PYTHON_RUNTIME_PLATFORM})
Set(SP_PYTHON_RUNTIME_DIR  ${CMAKE_BINARY_DIR}/python-runtime)

If(SP_PYTHON_RUNTIME_ARCHIVE)
    Set(_archive ${SP_PYTHON_RUNTIME_ARCHIVE})
    Message(STATUS "Python runtime: ${_archive} (local, not verified)")
Else()
    Set(_archive ${CMAKE_BINARY_DIR}/${SP_PYTHON_RUNTIME_NAME}.tar.gz)
    Set(_url ${SP_PYTHON_RUNTIME_URL_BASE}/${SP_PYTHON_RUNTIME_RELEASE}/${SP_PYTHON_RUNTIME_NAME}.tar.gz)
    If(NOT EXISTS ${_archive})
        Message(STATUS "Python runtime: downloading ${_url}")
        File(DOWNLOAD ${_url} ${_archive}.part
            EXPECTED_HASH SHA256=${SP_PYTHON_RUNTIME_SHA256}
            TLS_VERIFY ON
            STATUS _status
        )
        List(GET _status 0 _code)
        If(NOT _code EQUAL 0)
            File(REMOVE ${_archive}.part)
            Message(FATAL_ERROR "Python runtime download failed: ${_status}")
        EndIf()
        File(RENAME ${_archive}.part ${_archive})
    EndIf()
    File(SHA256 ${_archive} _sha)
    If(NOT _sha STREQUAL SP_PYTHON_RUNTIME_SHA256)
        Message(FATAL_ERROR "Python runtime ${_archive}: sha256 ${_sha}, expected ${SP_PYTHON_RUNTIME_SHA256}")
    EndIf()
EndIf()

# Unpack (again whenever the archive changes).
File(SHA256 ${_archive} _sha)
If(NOT EXISTS ${SP_PYTHON_RUNTIME_DIR}/.sha256 OR NOT EXISTS ${SP_PYTHON_RUNTIME_DIR}/manifest.txt)
    Set(_unpack TRUE)
Else()
    File(READ ${SP_PYTHON_RUNTIME_DIR}/.sha256 _unpacked)
    If(NOT _unpacked STREQUAL _sha)
        Set(_unpack TRUE)
    EndIf()
EndIf()
If(_unpack)
    File(REMOVE_RECURSE ${SP_PYTHON_RUNTIME_DIR} ${CMAKE_BINARY_DIR}/python-runtime.tmp)
    File(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/python-runtime.tmp)
    Execute_Process(
        COMMAND ${CMAKE_COMMAND} -E tar xzf ${_archive}
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/python-runtime.tmp
        RESULT_VARIABLE _rc
    )
    If(NOT _rc EQUAL 0)
        Message(FATAL_ERROR "Could not unpack ${_archive}")
    EndIf()
    File(GLOB _top LIST_DIRECTORIES TRUE ${CMAKE_BINARY_DIR}/python-runtime.tmp/sp-python-*)
    File(RENAME ${_top} ${SP_PYTHON_RUNTIME_DIR})
    File(REMOVE_RECURSE ${CMAKE_BINARY_DIR}/python-runtime.tmp)
    File(WRITE ${SP_PYTHON_RUNTIME_DIR}/.sha256 ${_sha})
EndIf()

# manifest.txt: key=value lines -> SP_PYTHON_RUNTIME_<KEY>
File(STRINGS ${SP_PYTHON_RUNTIME_DIR}/manifest.txt _manifest)
ForEach(_line ${_manifest})
    String(REGEX MATCH "^([a-z_]+)=(.*)$" _m "${_line}")
    If(_m)
        String(TOUPPER ${CMAKE_MATCH_1} _key)
        Set(SP_PYTHON_RUNTIME_${_key} ${CMAKE_MATCH_2})
    EndIf()
EndForEach()
Message(STATUS "Python runtime: ${SP_PYTHON_RUNTIME_RELEASE} (Python ${SP_PYTHON_RUNTIME_PYTHON}, ${SP_PYTHON_RUNTIME_SOABI})")

String(REPLACE "." "" _pyn ${SP_PYTHON_RUNTIME_PYTHON_ABI})
Set(PYTHONSDK_INCLUDE    ${SP_PYTHON_RUNTIME_DIR}/build/include/python${SP_PYTHON_RUNTIME_PYTHON_ABI})
Set(PYTHONSDK_LIB        ${SP_PYTHON_RUNTIME_DIR}/build/lib)
Set(PYTHONSDK_LIBPYTHON  ${SP_PYTHON_RUNTIME_LIBPYTHON})
Set(PYTHONSDK_LIBS
    ${PYTHONSDK_LIB}/libpython${SP_PYTHON_RUNTIME_PYTHON_ABI}.a
    ${PYTHONSDK_LIB}/${SP_PYTHON_RUNTIME_LIBPYTHON}
    ${PYTHONSDK_LIB}/libboost_python${_pyn}.a
)
