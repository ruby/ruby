# History: this first caught "[BUG] try to mark T_NONE object" from
# rb_managed_id_table_dup (the COW growth of a shape's edge table)
# forgetting the born-shareable pin that rb_managed_id_table_create has
# (fixed in 14144837d, design_v2.md section 2.4-1).
#
# After that fix it still crashed ~9% of runs, with a DIFFERENT root
# cause that this same churn happens to drive: the global mark hits a
# T_NONE under thread_mark (parent: VM/thread/Thread, or out-of-heap
# once the thread's page is reclaimed too) at th->thgroup. A Ractor's
# main Thread wrapper lives in the *creating* Ractor's objspace, so
# thread_mark never runs in the worker's own local GC; the worker's
# local roots (ractor_mark_unshareable_parts) marked the ec and fibers
# directly but missed thgroup (born in the worker's objspace at
# thread_do_start_proc), so the worker's local GC freed it while
# th->thgroup still pointed at it, and the next global mark walked the
# dangling edge. Fixed by rooting the whole thread-owned set from the
# Ractor's local roots (rb_thread_mark_owned_roots).
#
# Multi-Ractor generic-ivar churn drives the shape transitions
# (String/Array hosts: set, read, drop hosts so local sweeps delete)
# while main reads ivars of frozen shareable hosts and everyone GCs;
# the worker-driven full (global) GC then does the offending mark.
# Also exercises the generic_fields_lock added for M1b.
sh = 100.times.map do |i|
  s = "host-#{i}"
  s.instance_variable_set(:@tag, "tag-#{i}".freeze)
  Ractor.make_shareable(s)
end

rs = 8.times.map do
  Ractor.new do
    ring = []
    30_000.times do |k|
      h = "h#{k}"             # String host
      h.instance_variable_set(:@a, [k, k * 2])
      h.instance_variable_set(:@b, "v#{k}")
      a = [k]                  # Array host
      a.instance_variable_set(:@c, k)
      ring << h << a
      ring.shift(2) if ring.size > 64
      if k % 7_000 == 0
        GC.start(full_mark: false)
        GC.start if k % 21_000 == 0
      end
    end
    :done
  end
end

ok = true
60.times do
  sh.each_with_index { |s, i| ok &&= (s.instance_variable_get(:@tag) == "tag-#{i}") }
  10_000.times { |k| t = +"m#{k}"; t.instance_variable_set(:@m, k) }
  GC.start(full_mark: false)
end
rs.each(&:join)
raise "shareable ivar mismatch" unless ok
puts "M1B_GEN_OK"
