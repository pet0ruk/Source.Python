# ------------------------------------------------------------------
# File: src/makefiles/python-runtime.cmake
# Purpose: Provides the Python runtime Source.Python is built against
#    and shipped with (Linux and Windows): a bundle from
#    https://github.com/pet0ruk/source-python-runtime (CPython, the
#    compiled site-packages and Boost.Python built for that exact
#    interpreter), pinned below by release and sha256.
#
#    The bundle is downloaded and unpacked into
#    <build dir>/python-runtime:
#      build/include, build/lib  headers (Python, all of Boost),
#                                libpython, Boost.Python
#      runtime/                  laid over the release tree (Python3/,
#                                compiled site-packages)
#      manifest.txt              versions (python_abi, libpython, ...)
#
#    One release, one asset per platform (Linux .tar.gz, Windows .zip),
#    each pinned by its sha256 (the release's SHA256SUMS).
#
#    Overrides (cmake -D...):
#      SP_PYTHON_RUNTIME_ARCHIVE  a local bundle archive to use instead
#                                 of downloading (not checksum-verified)
# ------------------------------------------------------------------
Set(SP_PYTHON_RUNTIME_RELEASE  3.13.17-r5)
If(WIN32 AND SP_X86_64)
    Set(SP_PYTHON_RUNTIME_PLATFORM win_amd64)
    Set(SP_PYTHON_RUNTIME_EXT      zip)
    Set(SP_PYTHON_RUNTIME_SHA256   4a405f91af431c147c16c1d7e074aa655c3516acb4bf3c3d63b6b7645b48b8ab)
ElseIf(WIN32)
    Set(SP_PYTHON_RUNTIME_PLATFORM win32)
    Set(SP_PYTHON_RUNTIME_EXT      zip)
    Set(SP_PYTHON_RUNTIME_SHA256   fe717e00caa6542302480b044dd12d53f968575ce1f03be85ec5f747b201737a)
ElseIf(SP_X86_64)
    Set(SP_PYTHON_RUNTIME_PLATFORM manylinux_2_28_x86_64)
    Set(SP_PYTHON_RUNTIME_EXT      tar.gz)
    Set(SP_PYTHON_RUNTIME_SHA256   cb616694dc029d976821165958e6d52c4e2714302b2c3376779943f306fcd523)
Else()
    Set(SP_PYTHON_RUNTIME_PLATFORM manylinux_2_28_i686)
    Set(SP_PYTHON_RUNTIME_EXT      tar.gz)
    Set(SP_PYTHON_RUNTIME_SHA256   e95f99b9f39117c9189335c760081b9c6ae468993417c0bcee577d988ddc8b1a)
EndIf()
Set(SP_PYTHON_RUNTIME_URL_BASE https://github.com/pet0ruk/source-python-runtime/releases/download)

Set(SP_PYTHON_RUNTIME_NAME sp-python-${SP_PYTHON_RUNTIME_RELEASE}-${SP_PYTHON_RUNTIME_PLATFORM})
Set(SP_PYTHON_RUNTIME_DIR  ${CMAKE_BINARY_DIR}/python-runtime)

If(SP_PYTHON_RUNTIME_ARCHIVE)
    Set(_archive ${SP_PYTHON_RUNTIME_ARCHIVE})
    Message(STATUS "Python runtime: ${_archive} (local, not verified)")
Else()
    Set(_archive ${CMAKE_BINARY_DIR}/${SP_PYTHON_RUNTIME_NAME}.${SP_PYTHON_RUNTIME_EXT})
    Set(_url ${SP_PYTHON_RUNTIME_URL_BASE}/${SP_PYTHON_RUNTIME_RELEASE}/${SP_PYTHON_RUNTIME_NAME}.${SP_PYTHON_RUNTIME_EXT})
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
        COMMAND ${CMAKE_COMMAND} -E tar xf ${_archive}
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
If(NOT SP_PYTHON_RUNTIME_BOOST_INCLUDE)
    Message(FATAL_ERROR "Python runtime ${SP_PYTHON_RUNTIME_RELEASE} has no Boost headers (manifest key boost_include); r2 or later is needed")
EndIf()
# Python's headers, and Boost's (the release Boost.Python was built from).
Set(PYTHONSDK_INCLUDE
    ${SP_PYTHON_RUNTIME_DIR}/build/include/python${SP_PYTHON_RUNTIME_PYTHON_ABI}
    ${SP_PYTHON_RUNTIME_DIR}/${SP_PYTHON_RUNTIME_BOOST_INCLUDE}
)
Set(PYTHONSDK_LIB        ${SP_PYTHON_RUNTIME_DIR}/build/lib)
# The file the loader loads from Python3/plat-<os>/ (libpython3.X.so.1.0 / python3X.dll).
Set(PYTHONSDK_LIBPYTHON  ${SP_PYTHON_RUNTIME_LIBPYTHON})
If(WIN32)
    Set(PYTHONSDK_LIBS
        ${PYTHONSDK_LIB}/${SP_PYTHON_RUNTIME_PYTHON_LIB}
        ${PYTHONSDK_LIB}/${SP_PYTHON_RUNTIME_BOOST_PYTHON_LIB}
    )
Else()
    # Only the shared libpython (the one the loader loads), not also libpython3.X.a: linking the
    # static library as well put a second, unused copy of the interpreter into core.so.
    Set(PYTHONSDK_LIBS
        ${PYTHONSDK_LIB}/${SP_PYTHON_RUNTIME_LIBPYTHON}
        ${PYTHONSDK_LIB}/libboost_python${_pyn}.a
    )
EndIf()
