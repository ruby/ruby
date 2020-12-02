# frozen_string_literal: false
require 'test/unit'
require 'tempfile'

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
      end
      assert(!bad)
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

  def test_errinfo_encoding_in_debug
    exc = Module.new {break class_eval("class C\u{30a8 30e9 30fc} < RuntimeError; self; end".encode(Encoding::EUC_JP))}
    exc.inspect

    err = EnvUtil.verbose_warning do
      assert_raise(exc) do
        $DEBUG, debug = true, $DEBUG
        begin
          raise exc
        ensure
          $DEBUG = debug
        end
      end
    end
    assert_include(err, exc.to_s)
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

  def test_catch_no_throw
    assert_equal(:foo, catch {:foo})
  end

  def test_catch_throw
    result = catch(:foo) {
      loop do
        loop do
          throw :foo, true
          break
        end
        assert(false, "should not reach here")
      end
      false
    }
    assert(result)
  end

  def test_catch_throw_noarg
    assert_nothing_raised(UncaughtThrowError) {
      result = catch {|obj|
        throw obj, :ok
        assert(false, "should not reach here")
      }
      assert_equal(:ok, result)
    }
  end

  def test_uncaught_throw
    tag = nil
    e = assert_raise_with_message(UncaughtThrowError, /uncaught throw/) {
      catch("foo") {|obj|
        tag = obj.dup
        throw tag, :ok
        assert(false, "should not reach here")
      }
      assert(false, "should not reach here")
    }
    assert_not_nil(tag)
    assert_same(tag, e.tag)
    assert_equal(:ok, e.value)
  end

  def test_catch_throw_in_require
    bug7185 = '[ruby-dev:46234]'
    Tempfile.create(["dep", ".rb"]) {|t|
      t.puts("throw :extdep, 42")
      t.close
      assert_equal(42, assert_throw(:extdep, bug7185) {require t.path}, bug7185)
    }
  end

  def test_throw_false
    bug12743 = '[ruby-core:77229] [Bug #12743]'
    Thread.start {
      e = assert_raise_with_message(UncaughtThrowError, /false/, bug12743) {
        throw false
      }
      assert_same(false, e.tag, bug12743)
    }.join
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

  def test_type_error_message_encoding
    c = eval("Module.new do break class C\u{4032}; self; end; end")
    o = c.new
    assert_raise_with_message(TypeError, /C\u{4032}/) do
      ""[o]
    end
    c.class_eval {def to_int; self; end}
    assert_raise_with_message(TypeError, /C\u{4032}/) do
      ""[o]
    end
    c.class_eval {def to_a; self; end}
    assert_raise_with_message(TypeError, /C\u{4032}/) do
      [*o]
    end
    obj = eval("class C\u{1f5ff}; self; end").new
    assert_raise_with_message(TypeError, /C\u{1f5ff}/) do
      Class.new {include obj}
    end
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
    skip
    _, stderr, _ = EnvUtil.invoke_ruby(%w"--disable-gems -d", <<-RUBY, false, true)
Thread.start do
  Thread.current.report_on_exception = false
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
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    bug5575 = '[ruby-core:41612]'
    begin;
      begin
        BasicObject.new.inspect
      rescue
        assert_nothing_raised(NameError, bug5575) {$!.inspect}
      end
    end;
  end

  def test_equal
    bug5865 = '[ruby-core:41979]'
    assert_equal(RuntimeError.new("a"), RuntimeError.new("a"), bug5865)
    assert_not_equal(RuntimeError.new("a"), StandardError.new("a"), bug5865)
  end

  def test_exception_in_exception_equal
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    bug5865 = '[ruby-core:41979]'
    begin;
      o = Object.new
      def o.exception(arg)
      end
      assert_nothing_raised(ArgumentError, bug5865) do
        RuntimeError.new("a") == o
      end
    end;
  end

  def test_backtrace_by_exception
    begin
      line = __LINE__; raise "foo"
    rescue => e
    end
    e2 = e.exception("bar")
    assert_not_equal(e.message, e2.message)
    assert_equal(e.backtrace, e2.backtrace)
    loc = e2.backtrace_locations[0]
    assert_equal([__FILE__, line], [loc.path, loc.lineno])
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

  def m
    m(&->{return 0})
    42
  end

  def test_stackoverflow
    feature6216 = '[ruby-core:43794] [Feature #6216]'
    e = assert_raise(SystemStackError, feature6216) {m}
    level = e.backtrace.size
    assert_operator(level, :>, 10, feature6216)

    feature6216 = '[ruby-core:63377] [Feature #6216]'
    e = assert_raise(SystemStackError, feature6216) {raise e}
    assert_equal(level, e.backtrace.size, feature6216)
  end

  def test_machine_stackoverflow
    bug9109 = '[ruby-dev:47804] [Bug #9109]'
    assert_separately(%w[--disable-gem], <<-SRC)
    assert_raise(SystemStackError, #{bug9109.dump}) {
      h = {a: ->{h[:a].call}}
      h[:a].call
    }
    SRC
  rescue SystemStackError
  end

  def test_machine_stackoverflow_by_define_method
    bug9454 = '[ruby-core:60113] [Bug #9454]'
    assert_separately(%w[--disable-gem], <<-SRC)
    assert_raise(SystemStackError, #{bug9454.dump}) {
      define_method(:foo) {self.foo}
      self.foo
    }
    SRC
  rescue SystemStackError
  end

  def test_machine_stackoverflow_by_trace
    assert_normal_exit("#{<<-"begin;"}\n#{<<~"end;"}", timeout: 60)
    begin;
      require 'timeout'
      require 'tracer'
      class HogeError < StandardError
        def to_s
          message.upcase        # disable tailcall optimization
        end
      end
      Tracer.stdout = open(IO::NULL, "w")
      begin
        Timeout.timeout(5) do
          Tracer.on
          HogeError.new.to_s
        end
      rescue Timeout::Error
        # ok. there are no SEGV or critical error
      rescue SystemStackError => e
        # ok.
      end
    end;
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
    e = assert_raise(RuntimeError) {
      begin
        raise msg
      rescue => e
        raise e
      end
    }
    assert_not_same(e, e.cause, "#{msg}: should not be recursive")
  end

  def test_cause_raised_in_rescue
    a = nil
    e = assert_raise_with_message(RuntimeError, 'b') {
      begin
        raise 'a'
      rescue => a
        begin
          raise 'b'
        rescue => b
          assert_same(a, b.cause)
          begin
            raise 'c'
          rescue
            raise b
          end
        end
      end
    }
    assert_same(a, e.cause, 'cause should not be overwritten by reraise')
  end

  def test_cause_at_raised
    a = nil
    e = assert_raise_with_message(RuntimeError, 'b') {
      begin
        raise 'a'
      rescue => a
        b = RuntimeError.new('b')
        assert_nil(b.cause)
        begin
          raise 'c'
        rescue
          raise b
        end
      end
    }
    assert_equal('c', e.cause.message, 'cause should be the exception at raised')
    assert_same(a, e.cause.cause)
  end

  def test_cause_at_end
    errs = [
      /-: unexpected return\n/,
      /.*undefined local variable or method `n'.*\n/,
    ]
    assert_in_out_err([], <<-'end;', [], errs)
      END{n}; END{return}
    end;
  end

  def test_raise_with_cause
    msg = "[Feature #8257]"
    cause = ArgumentError.new("foobar")
    e = assert_raise(RuntimeError) {raise msg, cause: cause}
    assert_same(cause, e.cause)
  end

  def test_cause_with_no_arguments
    cause = ArgumentError.new("foobar")
    assert_raise_with_message(ArgumentError, /with no arguments/) do
      raise cause: cause
    end
  end

  def test_raise_with_cause_in_rescue
    e = assert_raise_with_message(RuntimeError, 'b') {
      begin
        raise 'a'
      rescue => a
        begin
          raise 'b'
        rescue => b
          assert_same(a, b.cause)
          begin
            raise 'c'
          rescue
            raise b, cause: ArgumentError.new('d')
          end
        end
      end
    }
    assert_equal('d', e.cause.message, 'cause option should be honored always')
    assert_nil(e.cause.cause)
  end

  def test_cause_thread_no_cause
    bug12741 = '[ruby-core:77222] [Bug #12741]'

    x = Thread.current
    a = false
    y = Thread.start do
      Thread.pass until a
      x.raise "stop"
    end

    begin
      raise bug12741
    rescue
      e = assert_raise_with_message(RuntimeError, "stop") do
        a = true
        sleep 1
      end
    end
    assert_nil(e.cause)
  ensure
    y.join
  end

  def test_cause_thread_with_cause
    bug12741 = '[ruby-core:77222] [Bug #12741]'

    x = Thread.current
    q = Queue.new
    y = Thread.start do
      q.pop
      begin
        raise "caller's cause"
      rescue
        x.raise "stop"
      end
    end

    begin
      raise bug12741
    rescue
      e = assert_raise_with_message(RuntimeError, "stop") do
        q.push(true)
        sleep 1
      end
    ensure
      y.join
    end
    assert_equal("caller's cause", e.cause.message)
  end

  def test_unknown_option
    bug = '[ruby-core:63203] [Feature #8257] should pass unknown options'

    exc = Class.new(RuntimeError) do
      attr_reader :arg
      def initialize(msg = nil)
        @arg = msg
        super(msg)
      end
    end

    e = assert_raise(exc, bug) {raise exc, "foo" => "bar", foo: "bar"}
    assert_equal({"foo" => "bar", foo: "bar"}, e.arg, bug)

    e = assert_raise(exc, bug) {raise exc, "foo" => "bar", foo: "bar", cause: RuntimeError.new("zzz")}
    assert_equal({"foo" => "bar", foo: "bar"}, e.arg, bug)

    e = assert_raise(exc, bug) {raise exc, {}}
    assert_equal({}, e.arg, bug)
  end

  def test_circular_cause
    bug13043 = '[ruby-core:78688] [Bug #13043]'
    begin
      begin
        raise "error 1"
      ensure
        orig_error = $!
        begin
          raise "error 2"
        rescue => err
          raise orig_error
        end
      end
    rescue => x
    end
    assert_equal(orig_error, x)
    assert_equal(orig_error, err.cause)
    assert_nil(orig_error.cause, bug13043)
  end

  def test_cause_with_frozen_exception
    exc = ArgumentError.new("foo").freeze
    assert_raise_with_message(ArgumentError, exc.message) {
      raise exc, cause: RuntimeError.new("bar")
    }
  end

  def test_cause_exception_in_cause_message
    assert_in_out_err([], "#{<<~"begin;"}\n#{<<~'end;'}") do |outs, errs, status|
      begin;
        exc = Class.new(StandardError) do
          def initialize(obj, cnt)
            super(obj)
            @errcnt = cnt
          end
          def to_s
            return super if @errcnt <= 0
            @errcnt -= 1
            raise "xxx"
          end
        end.new("ok", 10)
        raise "[Bug #17033]", cause: exc
      end;
      assert_equal(1, errs.count {|m| m.include?("[Bug #17033]")}, proc {errs.pretty_inspect})
    end
  end

  def test_anonymous_message
    assert_in_out_err([], "raise Class.new(RuntimeError), 'foo'", [], /foo\n/)
  end

  def test_output_string_encoding
    # "\x82\xa0" in cp932 is "\u3042" (Japanese hiragana 'a')
    # change $stderr to force calling rb_io_write() instead of fwrite()
    assert_in_out_err(["-Eutf-8:cp932"], '# coding: cp932
$stderr = $stdout; raise "\x82\xa0"') do |outs, errs, status|
      assert_equal 1, outs.size
      assert_equal 0, errs.size
      err = outs.first.force_encoding('utf-8')
      assert err.valid_encoding?, 'must be valid encoding'
      assert_match %r/\u3042/, err
    end
  end

  def test_multibyte_and_newline
    bug10727 = '[ruby-core:67473] [Bug #10727]'
    assert_in_out_err([], <<-'end;', [], /\u{306b 307b 3093 3054} \(E\)\n\u{6539 884c}/, bug10727, encoding: "UTF-8")
      class E < StandardError
        def initialize
          super("\u{306b 307b 3093 3054}\n\u{6539 884c}")
        end
      end
      raise E
    end;
  end

  def assert_null_char(src, *args, **opts)
    begin
      eval(src)
    rescue => e
    end
    assert_not_nil(e)
    assert_include(e.message, "\0")
    assert_in_out_err([], src, [], [], *args, **opts) do |_, err,|
      err.each do |e|
        assert_not_include(e, "\0")
      end
    end
    e
  end

  def test_control_in_message
    bug7574 = '[ruby-dev:46749]'
    assert_null_char("#{<<~"begin;"}\n#{<<~'end;'}", bug7574)
    begin;
      Object.const_defined?("String\0")
    end;
    assert_null_char("#{<<~"begin;"}\n#{<<~'end;'}", bug7574)
    begin;
      Object.const_get("String\0")
    end;
  end

  def test_encoding_in_message
    name = "\u{e9}t\u{e9}"
    e = EnvUtil.with_default_external("US-ASCII") do
      assert_raise(NameError) do
        Object.const_get(name)
      end
    end
    assert_include(e.message, name)
  end

  def test_method_missing_reason_clear
    bug10969 = '[ruby-core:68515] [Bug #10969]'
    a = Class.new {def method_missing(*) super end}.new
    assert_raise(NameError) {a.instance_eval("foo")}
    assert_raise(NoMethodError, bug10969) {a.public_send("bar", true)}
  end

  def test_message_of_name_error
    assert_raise_with_message(NameError, /\Aundefined method `foo' for module `#<Module:.*>'$/) do
      Module.new do
        module_function :foo
      end
    end
  end

  def capture_warning_warn(category: false)
    verbose = $VERBOSE
    deprecated = Warning[:deprecated]
    warning = []

    ::Warning.class_eval do
      alias_method :warn2, :warn
      remove_method :warn

      if category
        define_method(:warn) do |str, category: nil|
          warning << [str, category]
        end
      else
        define_method(:warn) do |str|
          warning << str
        end
      end
    end

    $VERBOSE = true
    Warning[:deprecated] = true
    yield

    return warning
  ensure
    $VERBOSE = verbose
    Warning[:deprecated] = deprecated

    ::Warning.class_eval do
      remove_method :warn
      alias_method :warn, :warn2
      remove_method :warn2
    end
  end

  def test_warning_warn
    warning = capture_warning_warn {@a}
    assert_match(/instance variable @a not initialized/, warning[0])

    assert_equal(["a\nz\n"], capture_warning_warn {warn "a\n", "z"})
    assert_equal([],         capture_warning_warn {warn})
    assert_equal(["\n"],     capture_warning_warn {warn ""})
  end

  def test_warn_deprecated_backwards_compatibility_category
    warning = capture_warning_warn { Dir.exists?("non-existent") }

    assert_match(/deprecated/, warning[0])
  end

  def test_warn_deprecated_category
    warning = capture_warning_warn(category: true) { Dir.exists?("non-existent") }

    assert_equal :deprecated, warning[0][1]
  end

  def test_warn_deprecated_to_remove_backwards_compatibility_category
    warning = capture_warning_warn { Object.new.tainted? }

    assert_match(/deprecated/, warning[0])
  end

  def test_warn_deprecated_to_remove_category
    warning = capture_warning_warn(category: true) { Object.new.tainted? }

    assert_equal :deprecated, warning[0][1]
  end

  def test_kernel_warn_uplevel
    warning = capture_warning_warn {warn("test warning", uplevel: 0)}
    assert_equal("#{__FILE__}:#{__LINE__-1}: warning: test warning\n", warning[0])
    def (obj = Object.new).w(n) warn("test warning", uplevel: n) end
    warning = capture_warning_warn {obj.w(0)}
    assert_equal("#{__FILE__}:#{__LINE__-2}: warning: test warning\n", warning[0])
    warning = capture_warning_warn {obj.w(1)}
    assert_equal("#{__FILE__}:#{__LINE__-1}: warning: test warning\n", warning[0])
    assert_raise(ArgumentError) {warn("test warning", uplevel: -1)}
    assert_in_out_err(["-e", "warn 'ok', uplevel: 1"], '', [], /warning:/)
    warning = capture_warning_warn {warn("test warning", {uplevel: 0})}
    assert_match(/test warning.*{:uplevel=>0}/m, warning[0])
    warning = capture_warning_warn {warn("test warning", **{uplevel: 0})}
    assert_equal("#{__FILE__}:#{__LINE__-1}: warning: test warning\n", warning[0])
    warning = capture_warning_warn {warn("test warning", {uplevel: 0}, **{})}
    assert_equal("test warning\n{:uplevel=>0}\n", warning[0])
    assert_raise(ArgumentError) {warn("test warning", foo: 1)}
  end

  def test_warning_warn_invalid_argument
    assert_raise(TypeError) do
      ::Warning.warn nil
    end
    assert_raise(TypeError) do
      ::Warning.warn 1
    end
    assert_raise(Encoding::CompatibilityError) do
      ::Warning.warn "\x00a\x00b\x00c".force_encoding("utf-16be")
    end
  end

  def test_warning_warn_circular_require_backtrace
    warning = nil
    path = nil
    Tempfile.create(%w[circular .rb]) do |t|
      path = File.realpath(t.path)
      basename = File.basename(path)
      t.puts "require '#{basename}'"
      t.close
      $LOAD_PATH.push(File.dirname(t))
      warning = capture_warning_warn {
        assert require(basename)
      }
    ensure
      $LOAD_PATH.pop
      $LOADED_FEATURES.delete(t.path)
    end
    assert_equal(1, warning.size)
    assert_match(/circular require/, warning.first)
    assert_match(/^\tfrom #{Regexp.escape(path)}:1:/, warning.first)
  end

  def test_warning_warn_super
    assert_in_out_err(%[-W0], "#{<<~"{#"}\n#{<<~'};'}", [], /instance variable @a not initialized/)
    {#
      module Warning
        def warn(message)
          super
        end
      end

      $VERBOSE = true
      @a
    };
  end

  def test_warning_category
    assert_raise(TypeError) {Warning[nil]}
    assert_raise(ArgumentError) {Warning[:XXXX]}
    assert_include([true, false], Warning[:deprecated])
    assert_include([true, false], Warning[:experimental])
  end

  def test_undefined_backtrace
    assert_separately([], "#{<<-"begin;"}\n#{<<-"end;"}")
    begin;
      class Exception
        undef backtrace
      end

      assert_raise(RuntimeError) {
        raise RuntimeError, "hello"
      }
    end;
  end

  def test_redefined_backtrace
    assert_separately([], "#{<<-"begin;"}\n#{<<-"end;"}")
    begin;
      $exc = nil

      class Exception
        undef backtrace
        def backtrace
          $exc = self
        end
      end

      e = assert_raise(RuntimeError) {
        raise RuntimeError, "hello"
      }
      assert_same(e, $exc)
    end;
  end

  def test_blocking_backtrace
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      class Bug < RuntimeError
        def backtrace
          IO.readlines(IO::NULL)
        end
      end
      bug = Bug.new '[ruby-core:85939] [Bug #14577]'
      n = 10000
      i = 0
      n.times do
        begin
          raise bug
        rescue Bug
          i += 1
        end
      end
      assert_equal(n, i)
    end;
  end

  def test_wrong_backtrace
    assert_separately([], "#{<<-"begin;"}\n#{<<-"end;"}")
    begin;
      class Exception
        undef backtrace
        def backtrace(a)
        end
      end

      assert_raise(RuntimeError) {
        raise RuntimeError, "hello"
      }
    end;

    error_class = Class.new(StandardError) do
      def backtrace; :backtrace; end
    end
    begin
      raise error_class
    rescue error_class => e
      assert_raise(TypeError) {$@}
      assert_raise(TypeError) {e.full_message}
    end
  end

  def test_backtrace_in_eval
    bug = '[ruby-core:84434] [Bug #14229]'
    assert_in_out_err(['-e', 'eval("raise")'], "", [], /^\(eval\):1:/, bug)
  end

  def test_full_message
    message = RuntimeError.new("testerror").full_message
    assert_operator(message, :end_with?, "\n")

    test_method = "def foo; raise 'testerror'; end"

    out1, err1, status1 = EnvUtil.invoke_ruby(['-e', "#{test_method}; begin; foo; rescue => e; puts e.full_message; end"], '', true, true)
    assert_predicate(status1, :success?)
    assert_empty(err1, "expected nothing wrote to $stdout by #full_message")

    _, err2, status1 = EnvUtil.invoke_ruby(['-e', "#{test_method}; begin; foo; end"], '', true, true)
    assert_equal(err2, out1)

    e = RuntimeError.new("a\n")
    message = assert_nothing_raised(ArgumentError, proc {e.pretty_inspect}) do
      e.full_message
    end
    assert_operator(message, :end_with?, "\n")
    message = message.gsub(/\e\[[\d;]*m/, '')
    assert_not_operator(message, :end_with?, "\n\n")
    e = RuntimeError.new("a\n\nb\n\nc")
    message = assert_nothing_raised(ArgumentError, proc {e.pretty_inspect}) do
      e.full_message
    end
    assert_all?(message.lines) do |m|
      /\e\[\d[;\d]*m[^\e]*\n/ !~ m
    end

    e = RuntimeError.new("testerror")
    message = e.full_message(highlight: false)
    assert_not_match(/\e/, message)

    bt = ["test:100", "test:99", "test:98", "test:1"]
    e = assert_raise(RuntimeError) {raise RuntimeError, "testerror", bt}

    bottom = "test:100: testerror (RuntimeError)\n"
    top = "test:1\n"
    remark = "Traceback (most recent call last):"

    message = e.full_message(highlight: false, order: :top)
    assert_not_match(/\e/, message)
    assert_operator(message.count("\n"), :>, 2)
    assert_operator(message, :start_with?, bottom)
    assert_operator(message, :end_with?, top)

    message = e.full_message(highlight: false, order: :bottom)
    assert_not_match(/\e/, message)
    assert_operator(message.count("\n"), :>, 2)
    assert_operator(message, :start_with?, remark)
    assert_operator(message, :end_with?, bottom)

    assert_raise_with_message(ArgumentError, /:top or :bottom/) {
      e.full_message(highlight: false, order: :middle)
    }

    message = e.full_message(highlight: true)
    assert_match(/\e/, message)
    assert_not_match(/(\e\[1)m\1/, message)
    e2 = assert_raise(RuntimeError) {raise RuntimeError, "", bt}
    assert_not_match(/(\e\[1)m\1/, e2.full_message(highlight: true))

    message = e.full_message
    if Exception.to_tty?
      assert_match(/\e/, message)
      message = message.gsub(/\e\[[\d;]*m/, '')
    else
      assert_not_match(/\e/, message)
    end
    assert_operator(message, :start_with?, bottom)
    assert_operator(message, :end_with?, top)
  end

  def test_exception_in_message
    code = "#{<<~"begin;"}\n#{<<~'end;'}"
    begin;
      class Bug14566 < StandardError
        def message; raise self.class; end
      end
      raise Bug14566
    end;
    assert_in_out_err([], code, [], /Bug14566/, success: false, timeout: 2)
  end

  def test_non_exception_cause
    assert_raise_with_message(TypeError, /exception/) do
      raise "foo", cause: 1
    end;
  end

  def test_circular_cause_handle
    assert_raise_with_message(ArgumentError, /circular cause/) do
      begin
        raise "error 1"
      rescue => e1
        raise "error 2" rescue raise e1, cause: $!
      end
    end;
  end

  def test_super_in_method_missing
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      $VERBOSE = nil
      class Object
        def method_missing(name, *args, &block)
          super
        end
      end

      bug14670 = '[ruby-dev:50522] [Bug #14670]'
      assert_raise_with_message(NoMethodError, /`foo'/, bug14670) do
        Object.new.foo
      end
    end;
  end
end
