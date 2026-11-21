/* config.h for building the hl2sdk's bundled protobuf 2.5.0 (see protobuf.cmake). It replaces
   the header protobuf's ./configure would generate; only these macros are used by libprotobuf. */

#define HAVE_HASH_MAP 1
#define HAVE_HASH_SET 1
#define HASH_MAP_H <unordered_map>
#define HASH_SET_H <unordered_set>
#define HASH_NAMESPACE std
#define HASH_MAP_CLASS unordered_map
#define HASH_SET_CLASS unordered_set

#define HAVE_PTHREAD 1

/* No zlib: gzip_stream is compiled empty, as nothing uses it. */
/* #undef HAVE_ZLIB */
