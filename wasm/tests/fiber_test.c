#include "wasm/fiber.h"
#include "wasm/asyncify.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

static rb_wasm_fiber_context fctx_main, fctx_func1, fctx_func2;

static int counter = 0;

static void func1(void *arg0, void *arg1) {
  assert(counter == 2);
  fprintf(stderr, "func1: started\n");
  fprintf(stderr, "func1: swapcontext(&fctx_func1, &fctx_func2)\n");
  counter++;
  rb_wasm_swapcontext(&fctx_func1, &fctx_func2);

  fprintf(stderr, "func1: returning\n");
}

static void func2(void *arg0, void *arg1) {
  assert(counter == 1);
  fprintf(stderr, "func2: started\n");
  fprintf(stderr, "func2: swapcontext(&fctx_func2, &fctx_func1)\n");
  counter++;
  rb_wasm_swapcontext(&fctx_func2, &fctx_func1);

  assert(counter == 3);
  fprintf(stderr, "func2: swapcontext(&fctx_func2, &fctx_func2)\n");
  counter++;
  rb_wasm_swapcontext(&fctx_func2, &fctx_func2);

  assert(counter == 4);
  fprintf(stderr, "func2: swapcontext(&fctx_func2, &fctx_main)\n");
  counter++;
  rb_wasm_swapcontext(&fctx_func2, &fctx_main);

  fprintf(stderr, "func2: returning\n");
  assert(false && "unreachable");
}

// top level function should not be inlined to stop unwinding immediately after this function returns
__attribute__((noinline))
int start(int argc, char **argv) {
  rb_wasm_init_context(&fctx_main, NULL, NULL, NULL);
  fctx_main.is_started = true;

  rb_wasm_init_context(&fctx_func1, func1, NULL, NULL);

  rb_wasm_init_context(&fctx_func2, func2, NULL, NULL);

  counter++;
  fprintf(stderr, "start: swapcontext(&uctx_main, &fctx_func2)\n");
  rb_wasm_swapcontext(&fctx_main, &fctx_func2);
  assert(counter == 5);

  fprintf(stderr, "start: exiting\n");
  return 42;
}

int main(int argc, char **argv) {
  extern int rb_wasm_rt_start(int (main)(int argc, char **argv), int argc, char **argv);
  int result = rb_wasm_rt_start(start, argc, argv);
  assert(result == 42);
  return 0;
}
