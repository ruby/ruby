Warning[:experimental] = false
GC.measure_total_time = true

workers = 4.times.map do |worker_id|
  Ractor.new(worker_id) do |id|
    Ractor.receive # Wait until all workers have been created.
    20.times do |batch|
      Array.new(10_000) { |i| "#{id}:#{batch}:#{i}".reverse }.sort!
    end
    GC.start(full_mark: false)
    {
      ractor: "worker-#{id}",
      marking_time_ms: GC.stat(:marking_time),
      sweeping_time_ms: GC.stat(:sweeping_time)
    }
  end
end

workers.each { |worker| worker.send(:start) }
workers.each { |worker| p worker.value }
p({
  ractor: "main",
  marking_time_ms: GC.stat(:marking_time),
  sweeping_time_ms: GC.stat(:sweeping_time)
})

puts "process-wide GC statistics:"
p GC.stat(process: true)
puts "process marking time (ms): #{GC.stat(:marking_time, process: true)}"
puts "process sweeping time (ms): #{GC.stat(:sweeping_time, process: true)}"
