#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_finish 1, %q{
  r, w = IO.pipe
  t1 = Thread.new { r.sysread(1) }
  t2 = Thread.new { r.sysread(1) }
  sleep 0.1
  w.write "a"
  sleep 0.1
  w.write "a"
}, '[ruby-dev:31866]'

assert_equal "[[nil, 1, 3, 3, 1, nil, nil], [nil, 2, 2, nil]]", %q{
  def tvar(var, val)
    old = Thread.current[var]
    begin
      Thread.current[var] = val
      yield
    ensure
      Thread.current[var] = old
    end
  end
  ary1 = []
  ary2 = []
  fb = Fiber.new {
    ary2 << Thread.current[:v]; tvar(:v, 2) {
    ary2 << Thread.current[:v];   Fiber.yield
    ary2 << Thread.current[:v]; }
    ary2 << Thread.current[:v]; Fiber.yield
    ary2 << Thread.current[:v]
  }
  ary1 << Thread.current[:v]; tvar(:v,1) {
  ary1 << Thread.current[:v];   tvar(:v,3) {
  ary1 << Thread.current[:v];     fb.resume
  ary1 << Thread.current[:v];   }
  ary1 << Thread.current[:v]; }
  ary1 << Thread.current[:v]; fb.resume
  ary1 << Thread.current[:v];
  [ary1, ary2]
}
