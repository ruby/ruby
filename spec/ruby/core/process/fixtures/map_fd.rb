fd = ARGV.shift.to_i

f = File.for_fd(fd)
f.autoclose = false
begin
  f.write "writing to fd: #{fd}"
ensure
  f.close
end
