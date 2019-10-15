1.times do
  puts Thread.current.backtrace_locations(1..1)[0].label
end
