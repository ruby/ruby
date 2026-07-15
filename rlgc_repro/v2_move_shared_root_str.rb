# RLGCv2: moving a CoW shared-ROOT string must not steal its buffer.
#
# Every STR_SHARED_ROOT is frozen (dup/substr of an unfrozen string
# interposes a hidden frozen root; str_replace_shared asserts the root is
# frozen). A frozen BARE string is shareable, so move passes it by
# reference and never captures it -- the steal is reachable only through
# a frozen root that is NOT shareable, i.e. one carrying an unshareable
# instance variable.
#
# rb_str_make_independent only un-shares a SHARER (STR_SHARED) and copies
# STR_NOFREE -- a root passes through untouched -- so the move courier
# used to steal the root's as.heap.ptr; after the receiver materialized,
# ractor_move_courier_free released the buffer and every surviving child
# read freed memory (ASAN: heap-use-after-free; production: silent
# corruption).
Warning[:experimental] = false

50.times do
  r = Ractor.new do
    v = Ractor.receive
    v.bytesize # touch
    :done
  end

  f = "x" * 4096
  f.instance_variable_set(:@x, []) # unshareable ivar => move, not passthrough
  f.freeze
  g = f.dup                # shares f's buffer -> f becomes STR_SHARED_ROOT
  h = f[10, 3000]          # long substring also shares f's buffer

  r.send(f, move: true)
  r.value

  GC.start                 # churn so a freed buffer gets poisoned/reused
  10.times { "z" * 4096 }

  raise "g corrupted: #{g[0, 8].inspect}" unless g == "x" * 4096
  raise "h corrupted" unless h == "x" * 3000
end
puts "OK v2_move_shared_root_str"
