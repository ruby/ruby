# IO.select performance. a lot of fd

ios = []
nr = 100
max = Process.getrlimit(Process::RLIMIT_NOFILE)[0]
puts "max fd: #{max} (results not apparent with <= 1024 max fd)"

(max - 10).times do
  r, w = IO.pipe
  r.close
  ios.push w
end

nr.times do
  IO.select nil, ios
end

