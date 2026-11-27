# Under M:N threads, a thread of a non-main Ractor may be resumed on another
# native thread after it blocks. If a C function caches the TLS address of
# ruby_current_ec across such a switch, it reads the ec of another native
# thread and crashes. Each test below blocks in Ruby code called back from
# such a C function.

# rb_f_raise
assert_equal 'ok', %q{
  class E < StandardError
    def exception(*) = (sleep 0.001; self)
  end
  8.times.map { Ractor.new { 50.times { raise E.new rescue nil } } }.each(&:join)
  :ok
}

# fiber_initialize
assert_equal 'ok', %q{
  class H < Hash
    def initialize_copy(*) = (sleep 0.001; super)
  end
  8.times.map { Ractor.new { 50.times { Fiber.new(storage: H.new) {}.resume } } }.each(&:join)
  :ok
}

# nurat_convert
assert_equal 'ok', %q{
  class N
    def to_int = (sleep 0.001; 3)
  end
  8.times.map { Ractor.new { 25.times { Rational(N.new, N.new) } } }.each(&:join)
  :ok
}

# f_complex_polar_real
assert_equal 'ok', %q{
  class N < Numeric
    def real? = true
    def coerce(o) = [self, self]
    def to_f = 1.0
    def *(o) = (sleep 0.001; 2)
    def +(o) = 3
  end
  8.times.map { Ractor.new { 25.times { Complex.polar(N.new, 2) } } }.each(&:join)
  :ok
}

# nurat_rationalize
assert_equal 'ok', %q{
  class Eps < Numeric
    def real? = true
    def abs = self
    def zero? = false
    def coerce(o) = (sleep 0.001; [o, 1r / 1_000_000_000])
  end
  8.times.map { Ractor.new { 25.times { (3r / 7).rationalize(Eps.new) } } }.each(&:join)
  :ok
}

# rb_complex_uminus
assert_equal 'ok', %q{
  class A < Numeric
    def real? = true
    def -@ = self
    def -(o) = (sleep 0.001; 5)
  end
  class B < Numeric
    def real? = true
    def -@ = Complex(1, 2)
  end
  8.times.map { Ractor.new { 50.times { -Complex.rect(A.new, B.new) } } }.each(&:join)
  :ok
}

# rb_complex_conjugate
assert_equal 'ok', %q{
  class A < Numeric
    def real? = true
    def -@ = self
    def -(o) = (sleep 0.001; 5)
  end
  class B < Numeric
    def real? = true
    def -@ = Complex(1, 2)
  end
  8.times.map { Ractor.new { 50.times { Complex.rect(A.new, B.new).conjugate } } }.each(&:join)
  :ok
}

# rb_complex_pow
assert_equal 'ok', %q{
  class Z < Numeric
    def ==(o) = (sleep 0.001; true)
  end
  8.times.map { Ractor.new { 50.times { Complex(1, 2) ** Z.new } } }.each(&:join)
  :ok
}

# rb_complex_pow (complex_pow_for_special_angle)
assert_equal 'ok', %q{
  class N < Numeric
    def real? = true
    def <(o) = (sleep 0.001; true)
    def -@ = 3
  end
  8.times.map { Ractor.new { 50.times { Complex.rect(N.new, 0) ** 2 } } }.each(&:join)
  :ok
}

# exec_recursive
assert_equal 'ok', %q{
  class Slow
    def inspect = (sleep 0.001; raise "boom")
  end
  8.times.map { Ractor.new { 50.times { [Slow.new].inspect rescue nil } } }.each(&:join)
  :ok
}

# exec_recursive (outermost)
assert_equal 'ok', %q{
  class SlowKey
    def hash = (sleep 0.001; raise "boom")
  end
  8.times.map { Ractor.new { h = {}; 50.times { (h[SlowKey.new] = 1) rescue nil } } }.each(&:join)
  :ok
}

# rb_thread_sleep_deadly
assert_equal 'ok', %q{
  class Ping < StandardError; end
  8.times.map do
    Ractor.new do
      finished = false
      sleeper = Thread.new do
        until finished
          begin
            Thread.handle_interrupt(Object => :never) { Thread.stop }
          rescue Ping
          end
        end
      end
      Thread.new do
        t_end = Time.now + 0.05
        while Time.now < t_end
          5.times { sleeper.raise(Ping) rescue nil; sleep 0.0005 }
          sleeper.wakeup rescue nil
          sleep 0.002
        end
        finished = true
      end.join
      sleeper.wakeup rescue nil until sleeper.join(0.001)
    end
  end.each(&:join)
  :ok
}

# mutex_lock_uninterruptible
assert_equal 'ok', %q{
  class Ping < StandardError; end
  8.times.map do
    Ractor.new do
      m = Mutex.new
      cv = ConditionVariable.new
      finished = false
      sleeper = Thread.new do
        until finished
          begin
            Thread.handle_interrupt(Object => :never) { m.synchronize { cv.wait(m) } }
          rescue Ping
          end
        end
      end
      Thread.new do
        t_end = Time.now + 0.05
        while Time.now < t_end
          m.synchronize do
            cv.signal
            5.times { sleeper.raise(Ping) rescue nil; sleep 0.0005 }
          end
          sleep 0.002
        end
        finished = true
      end.join
      m.synchronize { cv.broadcast } until sleeper.join(0.001)
    end
  end.each(&:join)
  :ok
}

# gc_finalize_deferred
assert_equal 'ok', %q{
  8.times.map do
    Ractor.new do
      10.times do
        4.times { ObjectSpace.define_finalizer(Object.new, proc { sleep 0.0005 }) }
        GC.start
        sleep 0.0001
      end
    end
  end.each(&:join)
  :ok
}

# rb_str_times
assert_equal 'ok', %q{
  class N
    def to_int = (sleep 0.001; 3)
  end
  8.times.map { Ractor.new { 50.times { "ab" * N.new } } }.each(&:join)
  :ok
}

# rb_const_search_from
assert_equal 'ok', %q{
  50.times do |i|
    path = File.expand_path("nt_switch_autoload_#{i}.rb")
    File.write(path, "sleep 0.001\n") # does not define the constant
    autoload :"C#{i}", path
  end
  8.times.map { Ractor.new { 50.times { |i| Object.const_get(:"C#{i}") rescue nil } } }.each(&:join)
  :ok
}

# rb_to_int
assert_equal 'ok', %q{
  class N
    def to_int = (sleep 0.001; 3)
  end
  8.times.map { Ractor.new { 50.times { [1, 2, 3, 4].first(N.new) } } }.each(&:join)
  :ok
}

# rb_check_integer_type
assert_equal 'ok', %q{
  class N
    def to_int = (sleep 0.001; 3)
  end
  8.times.map { Ractor.new { 50.times { "abc".byteslice(N.new) } } }.each(&:join)
  :ok
}

# rb_f_integer1
assert_equal 'ok', %q{
  class N
    def to_i = (sleep 0.001; 3)
  end
  8.times.map { Ractor.new { 50.times { Integer(N.new) } } }.each(&:join)
  :ok
}

# nucomp_s_new
assert_equal 'ok', %q{
  class N < Numeric
    def real? = (sleep 0.001; true)
  end
  8.times.map { Ractor.new { 50.times { Complex.rect(N.new) rescue nil } } }.each(&:join)
  :ok
}

# nucomp_s_polar
assert_equal 'ok', %q{
  class N < Numeric
    def real? = (sleep 0.001; true)
  end
  8.times.map { Ractor.new { 50.times { Complex.polar(N.new) rescue nil } } }.each(&:join)
  :ok
}

if /wasi|mswin|mingw/ !~ target_platform
  # detach_process_watcher
  assert_equal 'ok', %q{
    8.times.map do
      Ractor.new do
        10.times do
          ths = 2.times.map { Process.detach(Process.spawn("sleep", "0.001")) }
          ths.each { raise "bad #{it.value.inspect}" unless Process::Status === it.value }
        end
      end
    end.each(&:join)
    :ok
  }

  # proc_waitall
  assert_equal 'ok', %q{
    8.times.map do
      Ractor.new do
        12.times do
          4.times { Process.spawn("sleep", "0.001") }
          2.times.map { Thread.new { Process.waitall } }.each(&:join)
        end
      end
    end.each(&:join)
    :ok
  }

  # rb_thread_io_close_wait
  assert_equal 'ok', %q{
    12.times.map do
      Ractor.new do
        100.times do
          r, w = IO.pipe
          ths = 8.times.map { Thread.new { r.read rescue nil } }
          Thread.pass until ths.all? { it.status == "sleep" }
          r.close
          ths.each(&:join)
          w.close
        end
      end
    end.each(&:join)
    :ok
  }
end

# rb_error_frozen_object
assert_equal 'ok', %q{
  class F
    def self.to_s = (sleep 0.001; "F")
    def self.inspect = (sleep 0.001; "F")
  end
  8.times.map do
    Ractor.new do
      50.times do
        F.new.freeze.instance_variable_set(:@a, 1)
      rescue FrozenError
      end
    end
  end.each(&:join)
  :ok
}

# rb_ary_permutation
assert_equal 'ok', %q{
  8.times.map { Ractor.new { 12.times { n = 0; [*0...200].permutation(200) { sleep 0.001; break if (n += 1) > 5 } } } }.each(&:join)
  :ok
}

# rb_ary_repeated_combination
assert_equal 'ok', %q{
  8.times.map { Ractor.new { 12.times { n = 0; [1, 2].repeated_combination(200) { sleep 0.001; break if (n += 1) > 5 } } } }.each(&:join)
  :ok
}

# rb_ary_repeated_permutation
assert_equal 'ok', %q{
  8.times.map { Ractor.new { 12.times { n = 0; [1, 2].repeated_permutation(200) { sleep 0.001; break if (n += 1) > 5 } } } }.each(&:join)
  :ok
}

# rb_ary_transpose
assert_equal 'ok', %q{
  class A
    def initialize(slow) = @slow = slow
    def to_ary = (sleep 0.001 if @slow; [1, 2, 3])
  end
  8.times.map { Ractor.new { 2.times { Array.new(200) { A.new(it == 0) }.transpose } } }.each(&:join)
  :ok
}

# rb_str_split_m
assert_equal 'ok', %q{
  8.times.map { Ractor.new { 12.times { ",,".split(/(,)/) { sleep 0.001 } } } }.each(&:join)
  :ok
}

# ruby_float_step
assert_equal 'ok', %q{
  8.times.map { Ractor.new { 12.times { 1e300.step(2e300, 2e299) { sleep 0.001 } } } }.each(&:join)
  :ok
}
