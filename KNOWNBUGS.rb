#
# IMPORTANT: Always keep the first 7 lines (comments),
# even if this file is otherwise empty.
#
# This test file includes tests which point out known bugs.
# So all tests will cause failure.
#

assert_normal_exit %q{
  using Module.new
}

=begin
=================================================================
==43397==ERROR: AddressSanitizer: use-after-poison on address 0x62d000004028 at pc 0x000107ffd8b2 bp 0x7ffee87380d0 sp 0x7ffee87380c8
READ of size 8 at 0x62d000004028 thread T0
    #0 0x107ffd8b1 in invalidate_all_cc vm_method.c:243
    #1 0x107a891bf in objspace_each_objects_without_setup gc.c:3074
    #2 0x107ab6d4b in objspace_each_objects_protected gc.c:3084
    #3 0x107a5409b in rb_ensure eval.c:1137
    #4 0x107a88bcb in objspace_each_objects gc.c:3152
    #5 0x107a8888a in rb_objspace_each_objects gc.c:3136
    #6 0x107ffd843 in rb_clear_method_cache_all vm_method.c:259
    #7 0x107a55c9f in rb_using_module eval.c:1483
    #8 0x107a57dcf in top_using eval.c:1829
    #9 0x10806f65f in call_cfunc_1 vm_insnhelper.c:2439
    #10 0x108062ea5 in vm_call_cfunc_with_frame vm_insnhelper.c:2601
    #11 0x1080491b7 in vm_call_cfunc vm_insnhelper.c:2622
    #12 0x108048136 in vm_call_method_each_type vm_insnhelper.c:3100
    #13 0x108047507 in vm_call_method vm_insnhelper.c:3204
    #14 0x10800c03c in vm_call_general vm_insnhelper.c:3240
    #15 0x10803858e in vm_sendish vm_insnhelper.c:4194
    #16 0x107feb993 in vm_exec_core insns.def:799
    #17 0x1080223db in rb_vm_exec vm.c:1944
    #18 0x108026d2f in rb_iseq_eval_main vm.c:2201
    #19 0x107a4e863 in rb_ec_exec_node eval.c:296
    #20 0x107a4e323 in ruby_run_node eval.c:354
    #21 0x1074c2c94 in main main.c:50
    #22 0x7fff6b093cc8 in start (libdyld.dylib:x86_64+0x1acc8)

0x62d000004028 is located 40 bytes inside of 16384-byte region [0x62d000004000,0x62d000008000)
allocated by thread T0 here:
    #0 0x1086bf1c0 in wrap_posix_memalign (libclang_rt.asan_osx_dynamic.dylib:x86_64h+0x461c0)
    #1 0x107a9be2f in rb_aligned_malloc gc.c:9748
    #2 0x107ab26fd in heap_page_allocate gc.c:1771
    #3 0x107ab24a4 in heap_page_create gc.c:1875
    #4 0x107ab23e8 in heap_assign_page gc.c:1895
    #5 0x107a88093 in heap_add_pages gc.c:1908
    #6 0x107a87f8f in Init_heap gc.c:3030
    #7 0x107a4afd6 in ruby_setup eval.c:85
    #8 0x107a4b64c in ruby_init eval.c:108
    #9 0x1074c2c02 in main main.c:49
    #10 0x7fff6b093cc8 in start (libdyld.dylib:x86_64+0x1acc8)

SUMMARY: AddressSanitizer: use-after-poison vm_method.c:243 in invalidate_all_cc
Shadow bytes around the buggy address:
  0x1c5a000007b0: fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa
  0x1c5a000007c0: fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa
  0x1c5a000007d0: fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa
  0x1c5a000007e0: fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa
  0x1c5a000007f0: fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa
=>0x1c5a00000800: 00 00 00 00 00[f7]00 00 00 00 f7 00 00 00 00 f7
  0x1c5a00000810: 00 00 00 00 f7 00 00 00 00 f7 00 00 00 00 f7 00
  0x1c5a00000820: 00 00 00 f7 00 00 00 00 f7 00 00 00 00 f7 00 00
  0x1c5a00000830: 00 00 f7 00 00 00 00 f7 00 00 00 00 f7 00 00 00
  0x1c5a00000840: 00 f7 00 00 00 00 f7 00 00 00 00 f7 00 00 00 00
  0x1c5a00000850: f7 00 00 00 00 f7 00 00 00 00 f7 00 00 00 00 f7
Shadow byte legend (one shadow byte represents 8 application bytes):
  Addressable:           00
  Partially addressable: 01 02 03 04 05 06 07
  Heap left redzone:       fa
  Freed heap region:       fd
  Stack left redzone:      f1
  Stack mid redzone:       f2
  Stack right redzone:     f3
  Stack after return:      f5
  Stack use after scope:   f8
  Global redzone:          f9
  Global init order:       f6
  Poisoned by user:        f7
  Container overflow:      fc
  Array cookie:            ac
  Intra object redzone:    bb
  ASan internal:           fe
  Left alloca redzone:     ca
  Right alloca redzone:    cb
  Shadow gap:              cc
==43397==ABORTING
=end
