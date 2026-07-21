# RLGCv2 M1a: fstring interning from workers resizes the VM-global
# concurrent set on a worker thread, so the new table generation is
# allocated in the worker's objspace where no local root reaches it;
# the worker's confined GC then frees the live table (UAF for everyone).
# Fixed by making concurrent set objects born-shareable (pinned by the
# owning objspace's local GC). Same pattern: symbol.c id_entry_list.
N = 100000
puts 2.times.map{
  Ractor.new{
    N.times{|i| -(i.to_s)}
  }
}.map{|r| r.value}.join
