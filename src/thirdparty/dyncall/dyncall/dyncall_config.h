/*

 Package: dyncall
 Library: dyncall
 File: dyncall/dyncall_config.h
 Description: Macro configuration file for non-standard C types
 License:

   Copyright (c) 2007-2018 Daniel Adler <dadler@uni-goettingen.de>, 
                           Tassilo Philipp <tphilipp@potion-studios.com>

   Permission to use, copy, modify, and distribute this software for any
   purpose with or without fee is hereby granted, provided that the above
   copyright notice and this permission notice appear in all copies.

   THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
   WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
   MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
   ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
   WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
   ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
   OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

*/



/*

  dyncall type configuration

  REVISION
  2007/12/11 initial

*/

#ifndef DYNCALL_CONFIG_H
#define DYNCALL_CONFIG_H

#include "dyncall_macros.h"

/* Source.Python: bool is a real (one-byte) bool, so a called function's bool return value is
   read from al only, not the whole of eax (upstream Source.Python #419). C has no bool before
   C23, so the library itself is compiled with _Bool, which has the same layout. */
#if defined(__cplusplus)
#define DC_BOOL         bool
#else
#define DC_BOOL         _Bool
#endif
#define DC_LONG_LONG    long long
/* Source.Python: to its C++ code, pointers are passed and returned as integers, the type CPointer
   keeps addresses in (CPointer::m_ulAddr, a uintptr_t). The library itself keeps void*, which it
   is written for. Both are passed and returned the same way on every platform Source.Python
   builds for (an integer the size of a pointer, in the same registers). */
#if defined(__cplusplus)
#include <stdint.h>
#define DC_POINTER      uintptr_t
#else
#define DC_POINTER      void*
#endif

#endif /* DYNCALL_CONFIG_H */

