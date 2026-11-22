# ------------------------------------------------------------------
# File: src/makefiles/fetch.cmake
# Purpose: SP_Fetch_Source(<name> <url> <sha256>) downloads a source
#    archive, checks its sha256 and unpacks it into
#    <build dir>/_deps/<name>; sets <name>_SOURCE_DIR to the archive's
#    top-level directory. A download is kept and reused; the sources are
#    unpacked again when the pinned archive changes.
#
#    Override (cmake -D...): SP_<NAME>_SOURCE_DIR, an existing source
#    tree to use instead (e.g. a local checkout being worked on).
# ------------------------------------------------------------------
Function(SP_Fetch_Source _name _url _sha256)
    String(TOUPPER ${_name} _NAME)
    If(SP_${_NAME}_SOURCE_DIR)
        Message(STATUS "${_name}: ${SP_${_NAME}_SOURCE_DIR} (local)")
        Set(${_name}_SOURCE_DIR ${SP_${_NAME}_SOURCE_DIR} PARENT_SCOPE)
        Return()
    EndIf()

    Set(_deps ${CMAKE_BINARY_DIR}/_deps)
    Set(_archive ${_deps}/${_name}-${_sha256}.tar.gz)
    Set(_dir ${_deps}/${_name})
    If(NOT EXISTS ${_archive})
        Message(STATUS "${_name}: downloading ${_url}")
        File(DOWNLOAD ${_url} ${_archive}.part
            EXPECTED_HASH SHA256=${_sha256}
            TLS_VERIFY ON
            STATUS _status
        )
        List(GET _status 0 _code)
        If(NOT _code EQUAL 0)
            File(REMOVE ${_archive}.part)
            Message(FATAL_ERROR "${_name} download failed: ${_status}")
        EndIf()
        File(RENAME ${_archive}.part ${_archive})
    EndIf()

    Set(_stamp "")
    If(EXISTS ${_dir}/.sha256)
        File(READ ${_dir}/.sha256 _stamp)
    EndIf()
    If(NOT _stamp STREQUAL _sha256)
        File(REMOVE_RECURSE ${_dir} ${_dir}.tmp)
        File(ARCHIVE_EXTRACT INPUT ${_archive} DESTINATION ${_dir}.tmp)
        File(GLOB _top LIST_DIRECTORIES TRUE ${_dir}.tmp/*)
        List(LENGTH _top _count)
        If(NOT _count EQUAL 1)
            Message(FATAL_ERROR "${_archive}: expected one top-level directory")
        EndIf()
        File(RENAME ${_top} ${_dir})
        File(REMOVE_RECURSE ${_dir}.tmp)
        File(WRITE ${_dir}/.sha256 ${_sha256})
    EndIf()
    Set(${_name}_SOURCE_DIR ${_dir} PARENT_SCOPE)
EndFunction()
