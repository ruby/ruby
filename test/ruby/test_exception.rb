require 'test/unit'
require 'tempfile'
require_relative 'envutil'

class TestException < Test::Unit::TestCase
  def test_exception_rescued
    begin
      raise "this must be handled"
      assert(false)
    rescue
      assert(true)
    end
  end

  def test_exception_retry
    bad = true
    begin
      raise "this must be handled no.2"
    rescue
      if bad
        bad = false
        retry
        assert(false)
      end
    end
    assert(true)
  end

  def test_exception_in_rescue
    string = "this must be handled no.3"
    assert_raise_with_message(RuntimeError, string) do
      begin
        raise "exception in rescue clause"
      rescue
        raise string
      end
      assert(false)
    end
  end

  def test_exception_in_ensure
    string = "exception in ensure clause"
    assert_raise_with_message(RuntimeError, string) do
      begin
        raise "this must be handled no.4"
      ensure
        assert_instance_of(RuntimeError, $!)
        assert_equal("this must be handled no.4", $!.message)
        raise "exception in ensure clause"
      end
      assert(false)
    end
  end

  def test_exception_ensure
    bad = true
    begin
      begin
        raise "this must be handled no.5"
      ensure
        bad = false
      end
    rescue
    end
    assert(!bad)
  end

  def test_exception_ensure_2   # just duplication?
    bad = true
    begin
      begin
        raise "this must be handled no.6"
      ensure
        bad = false
      end
    rescue
    end
    assert(!bad)
  end

  def test_errinfo_in_debug
    bug9568 = EnvUtil.labeled_class("[ruby-core:61091] [Bug #9568]", RuntimeError) do
      def to_s
        require '\0'
      rescue LoadError
        self.class.to_s
      end
    end

    err = EnvUtil.verbose_warning do
      assert_raise(bug9568) do
        $DEBUG, debug = true, $DEBUG
        begin
          raise bug9568
        ensure
          $DEBUG = debug
        end
      end
    end
    assert_include(err, bug9568.to_s)
  end

  def test_break_ensure
    bad = true
    while true
      begin
        break
      ensure
        bad = false
      end
    end
    assert(!bad)
  end

  def test_catch_throw
    assert(catch(:foo) {
             loop do
               loop do
                 throw :foo, true
                 break
               end
               break
               assert(false)			# should no reach here
             end
             false
           })
  end

  def test_catch_throw_in_require
    bug7185 = '[ruby-dev:46234]'
    Tempfile.create(["dep", ".rb"]) {|t|
      t.puts("throw :extdep, 42")
      t.close
      assert_equal(42, catch(:extdep) {require t.path}, bug7185)
    }
  end

  def test_else_no_exception
    begin
      assert(true)
    rescue
      assert(false)
    else
      assert(true)
    end
  end

  def test_else_raised
    begin
      assert(true)
      raise
      assert(false)
    rescue
      assert(true)
    else
      assert(false)
    end
  end

  def test_else_nested_no_exception
    begin
      assert(true)
      begin
	assert(true)
      rescue
	assert(false)
      else
	assert(true)
      end
      assert(true)
    rescue
      assert(false)
    else
      assert(true)
    end
  end

  def test_else_nested_rescued
    begin
      assert(true)
      begin
	assert(true)
	raise
	assert(false)
      rescue
	assert(true)
      else
	assert(false)
      end
      assert(true)
    rescue
      assert(false)
    else
      assert(true)
    end
  end

  def test_else_nested_unrescued
    begin
      assert(true)
      begin
	assert(true)
      rescue
	assert(false)
      else
	assert(true)
      end
      assert(true)
      raise
      assert(false)
    rescue
      assert(true)
    else
      assert(false)
    end
  end

  def test_else_nested_rescued_reraise
    begin
      assert(true)
      begin
	assert(true)
	raise
	assert(false)
      rescue
	assert(true)
      else
	assert(false)
      end
      assert(true)
      raise
      assert(false)
    rescue
      assert(true)
    else
      assert(false)
    end
  end

  def test_raise_with_wrong_number_of_arguments
    assert_raise(TypeError) { raise nil }
    assert_raise(TypeError) { raise 1, 1 }
    assert_raise(ArgumentError) { raise 1, 1, 1, 1 }
  end

  def test_errat
    assert_in_out_err([], "p $@", %w(nil), [])

    assert_in_out_err([], "$@ = 1", [], /\$! not set \(ArgumentError\)$/)

    assert_in_out_err([], <<-INPUT, [], /backtrace must be Array of String \(TypeError\)$/)
      begin
        raise
      rescue
        $@ = 1
      end
    INPUT

    assert_in_out_err([], <<-INPUT, [], /^foo: unhandled exception$/)
      begin
        raise
      rescue
        $@ = 'foo'
        raise
      end
    INPUT

    assert_in_out_err([], <<-INPUT, [], /^foo: unhandled exception\s+from bar\s+from baz$/)
      begin
        raise
      rescue
        $@ = %w(foo bar baz)
        raise
      end
    INPUT
  end

  def test_thread_signal_location
    _, stderr, _ = EnvUtil.invoke_ruby("--disable-gems -d", <<-RUBY, false, true)
Thread.start do
  begin
    Process.kill(:INT, $$)
  ensure
    raise "in ensure"
  end
end.join
    RUBY
    assert_not_match(/:0/, stderr, "[ruby-dev:39116]")
  end

  def test_errinfo
    begin
      raise "foo"
      assert(false)
    rescue => e
      assert_equal(e, $!)
      1.times { assert_equal(e, $!) }
    end

    assert_equal(nil, $!)
  end

  def test_inspect
    assert_equal("#<Exception: Exception>", Exception.new.inspect)

    e = Class.new(Exception)
    e.class_eval do
      def to_s; ""; end
    end
    assert_equal(e.inspect, e.new.inspect)
  end

  def test_to_s
    e = StandardError.new("foo")
    assert_equal("foo", e.to_s)

    def (s = Object.new).to_s
      "bar"
    end
    e = StandardError.new(s)
    assert_equal("bar", e.to_s)
  end

  def test_set_backtrace
    e = Exception.new

    e.set_backtrace("foo")
    assert_equal(["foo"], e.backtrace)

    e.set_backtrace(%w(foo bar baz))
    assert_equal(%w(foo bar baz), e.backtrace)

    assert_raise(TypeError) { e.set_backtrace(1) }
    assert_raise(TypeError) { e.set_backtrace([1]) }
  end

  def test_exit_success_p
    begin
      exit
    rescue SystemExit => e
    end
    assert_send([e, :success?], "success by default")

    begin
      exit(true)
    rescue SystemExit => e
    end
    assert_send([e, :success?], "true means success")

    begin
      exit(false)
    rescue SystemExit => e
    end
    assert_not_send([e, :success?], "false means failure")

    begin
      abort
    rescue SystemExit => e
    end
    assert_not_send([e, :success?], "abort means failure")
  end

  def test_nomethoderror
    bug3237 = '[ruby-core:29948]'
    str = "\u2600"
    id = :"\u2604"
    msg = "undefined method `#{id}' for #{str.inspect}:String"
    assert_raise_with_message(NoMethodError, msg, bug3237) do
      str.__send__(id)
    end
  end

  def test_errno
    assert_equal(Encoding.find("locale"), Errno::EINVAL.new.message.encoding)
  end

  def test_too_many_args_in_eval
    bug5720 = '[ruby-core:41520]'
    arg_string = (0...140000).to_a.join(", ")
    assert_raise(SystemStackError, bug5720) {eval "raise(#{arg_string})"}
  end

  def test_systemexit_new
    e0 = SystemExit.new
    assert_equal(0, e0.status)
    assert_equal("SystemExit", e0.message)
    ei = SystemExit.new(3)
    assert_equal(3, ei.status)
    assert_equal("SystemExit", ei.message)
    es = SystemExit.new("msg")
    assert_equal(0, es.status)
    assert_equal("msg", es.message)
    eis = SystemExit.new(7, "msg")
    assert_equal(7, eis.status)
    assert_equal("msg", eis.message)

    bug5728 = '[ruby-dev:44951]'
    et = SystemExit.new(true)
    assert_equal(true, et.success?, bug5728)
    assert_equal("SystemExit", et.message, bug5728)
    ef = SystemExit.new(false)
    assert_equal(false, ef.success?, bug5728)
    assert_equal("SystemExit", ef.message, bug5728)
    ets = SystemExit.new(true, "msg")
    assert_equal(true, ets.success?, bug5728)
    assert_equal("msg", ets.message, bug5728)
    efs = SystemExit.new(false, "msg")
    assert_equal(false, efs.success?, bug5728)
    assert_equal("msg", efs.message, bug5728)
  end

  def test_exception_in_name_error_to_str
    bug5575 = '[ruby-core:41612]'
    Tempfile.create(["test_exception_in_name_error_to_str", ".rb"]) do |t|
      t.puts <<-EOC
      begin
        BasicObject.new.inspect
      rescue
        $!.inspect
      end
    EOC
      t.close
      assert_nothing_raised(NameError, bug5575) do
        load(t.path)
      end
    end
  end

  def test_equal
    bug5865 = '[ruby-core:41979]'
    assert_equal(RuntimeError.new("a"), RuntimeError.new("a"), bug5865)
    assert_not_equal(RuntimeError.new("a"), StandardError.new("a"), bug5865)
  end

  def test_exception_in_exception_equal
    bug5865 = '[ruby-core:41979]'
    Tempfile.create(["test_exception_in_exception_equal", ".rb"]) do |t|
      t.puts <<-EOC
      o = Object.new
      def o.exception(arg)
      end
      _ = RuntimeError.new("a") == o
      EOC
      t.close
      assert_nothing_raised(ArgumentError, bug5865) do
        load(t.path)
      end
    end
  end

  Bug4438 = '[ruby-core:35364]'

  def test_rescue_single_argument
    assert_raise(TypeError, Bug4438) do
      begin
        raise
      rescue 1
      end
    end
  end

  def test_rescue_splat_argument
    assert_raise(TypeError, Bug4438) do
      begin
        raise
      rescue *Array(1)
      end
    end
  end

  def test_to_s_taintness_propagation
    for exc in [Exception, NameError]
      m = "abcdefg"
      e = exc.new(m)
      e.taint
      s = e.to_s
      assert_equal(false, m.tainted?,
                   "#{exc}#to_s should not propagate taintness")
      assert_equal(false, s.tainted?,
                   "#{exc}#to_s should not propagate taintness")
    end

    o = Object.new
    def o.to_str
      "foo"
    end
    o.taint
    e = NameError.new(o)
    s = e.to_s
    assert_equal(false, s.tainted?)
  end

  def m;
    m &->{return 0};
    42;
  end

  def test_stackoverflow
    assert_raise(SystemStackError){m}
  end

  def test_machine_stackoverflow
    bug9109 = '[ruby-dev:47804] [Bug #9109]'
    assert_separately([], <<-SRC)
    assert_raise(SystemStackError, #{bug9109.dump}) {
      h = {a: ->{h[:a].call}}
      h[:a].call
    }
    SRC
  rescue SystemStackError
  end

  def test_machine_stackoverflow_by_define_method
    bug9454 = '[ruby-core:60113] [Bug #9454]'
    assert_separately([], <<-SRC)
    assert_raise(SystemStackError, #{bug9454.dump}) {
      define_method(:foo) {self.foo}
      self.foo
    }
    SRC
  rescue SystemStackError
  end

  def test_cause
    msg = "[Feature #8257]"
    cause = nil
    e = assert_raise(StandardError) {
      begin
        raise msg
      rescue => e
        cause = e.cause
        raise StandardError
      end
    }
    assert_nil(cause, msg)
    cause = e.cause
    assert_instance_of(RuntimeError, cause, msg)
    assert_equal(msg, cause.message, msg)
  end

  def test_cause_reraised
    msg = "[Feature #8257]"
    cause = nil
    e = assert_raise(RuntimeError) {
      begin
        raise msg
      rescue => e
        raise e
      end
    }
    assert_not_same(e, e.cause, "#{msg}: should not be recursive")
  end
end
