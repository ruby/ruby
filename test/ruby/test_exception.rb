require 'test/unit'

class JunkError < ZeroDivisionError
  def self.new(message)
    42
  end
end

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

    e = assert_raise(TypeError) { raise JunkError.new("abc") }
    assert_equal('exception class/object expected', e.message)

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
end
