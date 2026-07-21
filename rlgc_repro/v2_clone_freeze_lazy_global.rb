# RLGCv2 M1a: the first clone(freeze: true/false) in the process lazily
# creates freeze_true_hash/freeze_false_hash and registers them with
# rb_vm_register_global_object. When that first call happens on a worker,
# the hash lives in the worker objspace but the VM-global pin list used to
# be scanned only by main (which foreign-skips it) -> worker GC frees it.
# Fixed by walking the VM-global registration lists from every objspace.
rs = 4.times.map do
  Ractor.new do
    o = Object.new.freeze
    20_000.times do |i|
      o.clone(freeze: true)
      o.clone(freeze: false)
      Object.new.to_s * 8 if i % 64 == 0
    end
    GC.start
    :ok
  end
end
res = rs.map(&:value)
# main uses the same statics after workers are gone
GC.start
1000.times { Object.new.freeze.clone(freeze: true) }
puts res.inspect
