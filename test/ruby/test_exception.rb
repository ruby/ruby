require 'test/unit'
require_relative 'envutil'

class TestException < Test::Unit::TestCase
  def ruby(*r, &b)
    EnvUtil.rubyexec(*r, &b)
  end

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
    e = assert_raises(RuntimeError) do
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
    e = assert_raises(RuntimeError) do
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
    ruby do |w, r, e|
      w.puts "p $@"
      w.close
      assert_equal("nil", r.read.chomp)
      assert_equal("", e.read.chomp)
    end

    ruby do |w, r, e|
      w.puts "$@ = 1"
      w.close
      assert_equal("", r.read.chomp)
      assert_match(/\$! not set \(ArgumentError\)$/, e.read.chomp)
    end

    ruby do |w, r, e|
      w.puts "begin"
      w.puts "  raise"
      w.puts "rescue"
      w.puts "  $@ = 1"
      w.puts "end"
      w.close
      assert_equal("", r.read.chomp)
      assert_match(/backtrace must be Array of String \(TypeError\)$/, e.read.chomp)
    end

    ruby do |w, r, e|
      w.puts "begin"
      w.puts "  raise"
      w.puts "rescue"
      w.puts "  $@ = 'foo'"
      w.puts "  raise"
      w.puts "end"
      w.close
      assert_equal("", r.read.chomp)
      assert_match(/^foo: unhandled exception$/, e.read.chomp)
    end

    ruby do |w, r, e|
      w.puts "begin"
      w.puts "  raise"
      w.puts "rescue"
      w.puts "  $@ = %w(foo bar baz)"
      w.puts "  raise"
      w.puts "end"
      w.close
      assert_equal("", r.read.chomp)
      assert_match(/^foo: unhandled exception\s+from bar\s+from baz$/, e.read.chomp)
    end
  end
end
