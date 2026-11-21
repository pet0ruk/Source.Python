# ------------------------------------------------------------------
# File: src/makefiles/protobuf/protobuf.cmake
# Purpose: Builds libprotobuf (2.5.0) from the source the hl2sdk ships
#    in common/protobuf-2.5.0, for the engines that use protobuf
#    (csgo, blade) on Linux.
#
#    The SDK's prebuilt lib/linux32/release/libprotobuf.a was compiled
#    with GCC 4.7, i.e. with the old std::string ABI, so every
#    protobuf function taking or returning a std::string is missing
#    for code compiled with GCC >= 5 and core.so fails to load with
#    "undefined symbol". Building it here with the same compiler and
#    flags as core keeps the two in step.
#
#    The sources are the libprotobuf_la_SOURCES of the SDK's
#    Makefile.am (the same objects as the prebuilt archive).
# ------------------------------------------------------------------
Set(PROTOBUF_SRC ${SOURCESDK}/common/protobuf-2.5.0/src/google/protobuf)

Add_Library(protobuf STATIC
    ${PROTOBUF_SRC}/stubs/atomicops_internals_x86_gcc.cc
    ${PROTOBUF_SRC}/stubs/atomicops_internals_x86_msvc.cc
    ${PROTOBUF_SRC}/stubs/common.cc
    ${PROTOBUF_SRC}/stubs/once.cc
    ${PROTOBUF_SRC}/stubs/stringprintf.cc
    ${PROTOBUF_SRC}/extension_set.cc
    ${PROTOBUF_SRC}/generated_message_util.cc
    ${PROTOBUF_SRC}/message_lite.cc
    ${PROTOBUF_SRC}/repeated_field.cc
    ${PROTOBUF_SRC}/wire_format_lite.cc
    ${PROTOBUF_SRC}/io/coded_stream.cc
    ${PROTOBUF_SRC}/io/zero_copy_stream.cc
    ${PROTOBUF_SRC}/io/zero_copy_stream_impl_lite.cc
    ${PROTOBUF_SRC}/stubs/strutil.cc
    ${PROTOBUF_SRC}/stubs/substitute.cc
    ${PROTOBUF_SRC}/stubs/structurally_valid.cc
    ${PROTOBUF_SRC}/descriptor.cc
    ${PROTOBUF_SRC}/descriptor.pb.cc
    ${PROTOBUF_SRC}/descriptor_database.cc
    ${PROTOBUF_SRC}/dynamic_message.cc
    ${PROTOBUF_SRC}/extension_set_heavy.cc
    ${PROTOBUF_SRC}/generated_message_reflection.cc
    ${PROTOBUF_SRC}/message.cc
    ${PROTOBUF_SRC}/reflection_ops.cc
    ${PROTOBUF_SRC}/service.cc
    ${PROTOBUF_SRC}/text_format.cc
    ${PROTOBUF_SRC}/unknown_field_set.cc
    ${PROTOBUF_SRC}/wire_format.cc
    ${PROTOBUF_SRC}/io/gzip_stream.cc
    ${PROTOBUF_SRC}/io/printer.cc
    ${PROTOBUF_SRC}/io/tokenizer.cc
    ${PROTOBUF_SRC}/io/zero_copy_stream_impl.cc
    ${PROTOBUF_SRC}/compiler/importer.cc
    ${PROTOBUF_SRC}/compiler/parser.cc
)

# libprotobuf.a, so -Wl,--exclude-libs,libprotobuf.a (linux.base.cmake)
# keeps its symbols out of core.so's exports.
Set_Target_Properties(protobuf PROPERTIES
    OUTPUT_NAME protobuf
    POSITION_INDEPENDENT_CODE ON
)

# config.h first, so no other config.h on the include path is picked up.
Target_Include_Directories(protobuf BEFORE PRIVATE
    ${CMAKE_CURRENT_LIST_DIR}
    ${SOURCESDK}/common/protobuf-2.5.0/src
)
