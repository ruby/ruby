#include "wasm/machine.h"
#include "wasm/setjmp.h"
#include "wasm/fiber.h"
#include "wasm/asyncify.h"
#include <stdlib.h>

int rb_wasm_rt_start(int (main)(int argc, char **argv), int argc, char **argv) {
  int result;
  void *asyncify_buf;

  bool new_fiber_started = false;
  void *arg0 = NULL, *arg1 = NULL;
  void (*fiber_entry_point)(void *, void *) = NULL;

  while (1) {
    if (fiber_entry_point) {
      fiber_entry_point(arg0, arg1);
    } else {
      result = main(argc, argv);
    }

    // NOTE: it's important to call 'asyncify_stop_unwind' here instead in rb_wasm_handle_jmp_unwind
    // because unless that, Asyncify inserts another unwind check here and it unwinds to the root frame.
    asyncify_stop_unwind();

    if ((asyncify_buf = rb_wasm_handle_jmp_unwind()) != NULL) {
      asyncify_start_rewind(asyncify_buf);
      continue;
    }
    if ((asyncify_buf = rb_wasm_handle_scan_unwind()) != NULL) {
      asyncify_start_rewind(asyncify_buf);
      continue;
    }

    asyncify_buf = rb_wasm_handle_fiber_unwind(&fiber_entry_point, &arg0, &arg1, &new_fiber_started);
    // Newly starting fiber doesn't have asyncify buffer yet, so don't rewind it for the first time entry
    if (asyncify_buf) {
      asyncify_start_rewind(asyncify_buf);
      continue;
    } else if (new_fiber_started) {
      continue;
    }

    break;
  }
  return result;
}
