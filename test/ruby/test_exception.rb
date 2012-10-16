require 'test/unit'

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

  def test_exception_to_s_should_not_propagate_untrustedness
    favorite_lang = "Ruby"

    for exc in [Exception, NameError]
      assert_raise(SecurityError) do
        lambda {
          $SAFE = 4
          exc.new(favorite_lang).to_s
          favorite_lang.replace("Python")
        }.call
      end
    end

    assert_raise(SecurityError) do
      lambda {
        $SAFE = 4
        o = Object.new
        (class << o; self; end).send(:define_method, :to_str) {
          favorite_lang
        }
        NameError.new(o).to_s
        favorite_lang.replace("Python")
      }.call
    end

    assert_equal("Ruby", favorite_lang)
  end
end
