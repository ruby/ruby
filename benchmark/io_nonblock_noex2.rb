nr = 1_000_000
i = 0
msg = '.'
buf = '.'
begin
  r, w = IO.pipe
  while i < nr
    i += 1
    w.write_nonblock(msg, exception: false)
    r.read_nonblock(1, buf, exception: false)
  end
rescue ArgumentError # old Rubies
  while i < nr
    i += 1
    w.write_nonblock(msg)
    r.read_nonblock(1, buf)
  end
ensure
  r.close
  w.close
end
