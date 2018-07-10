nr = 1_000_000
i = 0
msg = '.'
buf = '.'
noex = { exception: false }
begin
  r, w = IO.pipe
  while i < nr
    i += 1
    w.write_nonblock(msg, noex)
    r.read_nonblock(1, buf, noex)
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
