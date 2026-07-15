Warning[:experimental]=false
8.times.map do |id|
  Ractor.new(id) do |i|
    fibs=[]
    40.times do |k|
      fibs << Fiber.new { Fiber.yield k; k*2 }
      fibs.last.resume
      sleep(0.0003)                      # block -> MN NT migration
      (fibs.shift.resume if fibs.size>4 rescue nil)
    end
    :ok
  end
end.each(&:value)
puts "M7 ok"
