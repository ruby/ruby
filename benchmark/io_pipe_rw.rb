# Measure uncontended GVL performance via read/write with 1:1 threading
# If we switch to M:N threading, this will benchmark something else...
r, w = IO.pipe
src = '0'.freeze
dst = String.new
i = 0
while i < 1_000_000
  i += 1
  w.write(src)
  r.read(1, dst)
end
w.close
r.close
