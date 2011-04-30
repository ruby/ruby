# IO.select performance. worst case

ios = []
nr = 1000000
max = Process.getrlimit(Process::RLIMIT_NOFILE)[0]
puts "max fd: #{max} (results not apparent with <= 1024 max fd)"

((max / 2) - 2).times do
  ios.concat IO.pipe
end

last = [ ios[-1] ]
puts "last IO: #{last[0].inspect}"

nr.times do
  IO.select nil, last
end

