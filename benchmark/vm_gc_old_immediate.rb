old_object = Array.new(1_000_000){''}
30_000.times do
  GC.start(full_mark: false, immediate_sweep: true)
end
