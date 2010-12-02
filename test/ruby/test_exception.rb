require 'test/unit'
require_relative 'envutil'

class TestException < Test::Unit::TestCase
  def test_exception
    begin
      raise "this must be handled"
      assert(false)
    rescue
      assert(true)
    end

    $bad = true
    begin
      raise "this must be handled no.2"
    rescue
      if $bad
        $bad = false
        retry
        assert(false)
      end
    end
    assert(true)

    # exception in rescue clause
    $string = "this must be handled no.3"
    e = assert_raise(RuntimeError) do
      begin
        raise "exception in rescue clause"
      rescue
        raise $string
      end
      assert(false)
    end
    assert_equal($string, e.message)

    # exception in ensure clause
    $string = "exception in ensure clause"
    e = assert_raise(RuntimeError) do
      begin
        raise "this must be handled no.4"
      ensure
        assert_instance_of(RuntimeError, $!)
        assert_equal("this must be handled no.4", $!.message)
        raise "exception in ensure clause"
      end
      assert(false)
    end
    assert_equal($string, e.message)

    $bad = true
    begin
      begin
        raise "this must be handled no.5"
      ensure
        $bad = false
      end
    rescue
    end
    assert(!$bad)

    $bad = true
    begin
      begin
        raise "this must be handled no.6"
      ensure
        $bad = false
      end
    rescue
    end
    assert(!$bad)

    $bad = true
    while true
      begin
        break
      ensure
        $bad = false
      end
    end
    assert(!$bad)

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

  def test_else
    begin
      assert(true)
    rescue
      assert(false)
    else
      assert(true)
    end

    begin
      assert(true)
      raise
      assert(false)
    rescue
      assert(true)
    else
      assert(false)
    end

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

  def test_safe4
    cmd = proc{raise SystemExit}
    safe0_p = proc{|*args| args}

    test_proc = proc {
      $SAFE = 4
      begin
        cmd.call
      rescue SystemExit => e
        safe0_p["SystemExit: #{e.inspect}"]
        raise e
      rescue Exception => e
        safe0_p["Exception (NOT SystemExit): #{e.inspect}"]
        raise e
      end
    }
    assert_raise(SystemExit, '[ruby-dev:38760]') {test_proc.call}
  end

  def test_thread_signal_location
    stdout, stderr, status = EnvUtil.invoke_ruby("-d", <<-RUBY, false, true)
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
    assert(e.success?)

    begin
      abort
    rescue SystemExit => e
    end
    assert(!e.success?)
  end

  def test_nomethoderror
    bug3237 = '[ruby-core:29948]'
    str = "\u2600"
    id = :"\u2604"
    e = assert_raise(NoMethodError) {str.__send__(id)}
    assert_equal("undefined method `#{id}' for #{str.inspect}:String", e.message, bug3237)
  end

  def test_errno
    assert_equal(Encoding.find("locale"), Errno::EINVAL.new.message.encoding)
  end
end
