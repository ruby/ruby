# RLGCv2 regression repro (CHECK-mode): a GC triggered while a Ractor holds its
# own ractor lock (a Port send/receive that allocates) reaches the confined
# verify (check_rvalue_consistency) during mark -- which used to take a fresh
# no-barrier VM lock and trip rb_vm_lock_enter's ractor->VM deadlock guard once
# main's local GC stopped holding the VM lock for the whole GC (bec44cd55).
# Fix: the confined verify skips the VM lock while during_gc (default.c).
# Before the fix this asserted 8/8; after, clean.
80.times do |r|
  port = Ractor::Port.new
  workers = 4.times.map do |i|
    Ractor.new(port, i) do |port, id|
      begin
        loop do
          o = Ractor.receive
          break if o == :stop
          raise "boom#{id}" if o.is_a?(Array) && (o.size % 5 == 0) && rand < 0.3
          o << Object.new
          port.send([id, o.size]) rescue nil
        end
      rescue => e
      end
      :done
    end
  end
  400.times do |i|
    obj = Array.new((i % 15) + 1) { "x#{i}-#{_1}".dup }
    (workers[i % 4].send(obj, move: true) rescue nil)
    GC.start if i % 100 == 0
  end
  workers.each { |w| w.send(:stop) rescue nil }
  workers.each { |w| w.value rescue nil }
  GC.start
  GC.compact if r % 8 == 0
end
:ok
