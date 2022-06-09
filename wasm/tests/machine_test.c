#include <stdio.h>
#include <assert.h>
#include <stdint.h>
#include <stdbool.h>
#include "wasm/machine.h"
#include "wasm/asyncify.h"

void *rb_wasm_get_stack_pointer(void);

static void *base_stack_pointer = NULL;

int __attribute__((constructor)) record_base_sp(void) {
  base_stack_pointer = rb_wasm_get_stack_pointer();
  return 0;
}

void dump_memory(uint8_t *base, uint8_t *end) {
  size_t chunk_size = 16;

  for (uint8_t *ptr = base; ptr <= end; ptr += chunk_size) {
    printf("%p", ptr);
    for (size_t offset = 0; offset < chunk_size; offset++) {
      printf(" %02x", *(ptr + offset));
    }
    printf("\n");
  }
}

bool find_in_stack(uint32_t target, void *base, void *end) {
  for (uint32_t *ptr = base; ptr <= (uint32_t *)end; ptr++) {
    if (*ptr == target) {
      return true;
    }
  }
  return false;
}

void *_rb_wasm_stack_mem[2];
void rb_wasm_mark_mem_range(void *start, void *end) {
  _rb_wasm_stack_mem[0] = start;
  _rb_wasm_stack_mem[1] = end;
}

#define check_live(target, ctx) do {            \
    rb_wasm_scan_stack(rb_wasm_mark_mem_range); \
    _check_live(target, ctx);                   \
  } while (0);

void _check_live(uint32_t target, const char *ctx) {
  printf("checking %#x ... ", target);
  bool found_in_locals = false, found_in_stack = false;
  if (find_in_stack(target, _rb_wasm_stack_mem[0], _rb_wasm_stack_mem[1])) {
    found_in_stack = true;
  }
  rb_wasm_scan_locals(rb_wasm_mark_mem_range);
  if (find_in_stack(target, _rb_wasm_stack_mem[0], _rb_wasm_stack_mem[1])) {
    found_in_locals = true;
  }
  if (found_in_locals && found_in_stack) {
    printf("ok (found in C stack and Wasm locals)\n");
  } else if (found_in_stack) {
    printf("ok (found in C stack)\n");
  } else if (found_in_locals) {
    printf("ok (found in Wasm locals)\n");
  } else {
    printf("not found: %s\n", ctx);
    assert(false);
  }
}

void new_frame(uint32_t val, uint32_t depth) {
  if (depth == 0) {
    dump_memory(rb_wasm_get_stack_pointer(), base_stack_pointer);
    for (uint32_t i = 0; i < 5; i++) {
      check_live(0x00bab10c + i, "argument value");
    }
  } else {
    new_frame(val, depth - 1);
  }
}

uint32_t return_value(void) {
  return 0xabadbabe;
}

uint32_t check_return_value(void) {
  check_live(0xabadbabe, "returned value");
  return 0;
}

void take_two_args(uint32_t a, uint32_t b) {
}

__attribute__((noinline))
int start(int argc, char **argv) {

  uint32_t deadbeef;
  register uint32_t facefeed;
  deadbeef = 0xdeadbeef;
  facefeed = 0xfacefeed;

  check_live(0xdeadbeef, "local variable");
  check_live(0xfacefeed, "local reg variable");

  new_frame(0x00bab10c, 5);

  take_two_args(return_value(), check_return_value());

  return 0;
}

int main(int argc, char **argv) {
  extern int rb_wasm_rt_start(int (main)(int argc, char **argv), int argc, char **argv);
  return rb_wasm_rt_start(start, argc, argv);
}
