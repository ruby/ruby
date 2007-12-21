#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_equal '0', %q{
  GC.stress = true
  pid = fork {}
  Process.wait pid
  $?.to_i
}, '[ruby-dev:32404]'

assert_equal 'ok', %q{
  1.times{
    eval("break")
  }
  :ok
}, '[ruby-dev:32525]'

assert_finish 2, %q{
  require "io/nonblock"
  r, w = IO.pipe
  w.nonblock = true
  w.write_nonblock("a" * 100000)
  w.nonblock = false
  t1 = Thread.new { w.write("b" * 4096) }
  t2 = Thread.new { w.write("c" * 4096) }
  sleep 0.5
  r.sysread(4096).length
  sleep 0.5
  r.sysread(4096).length
  t1.join
  t2.join
}, '[ruby-dev:32566]'
