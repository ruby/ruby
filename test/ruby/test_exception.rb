require 'test/unit'

$KCODE = 'none'

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
    begin
      begin
        raise "exception in rescue clause"
      rescue 
        raise $string
      end
      assert(false)
    rescue
      assert(true) if $! == $string
    end
      
    # exception in ensure clause
    begin
      begin
        raise "this must be handled no.4"
      ensure 
        raise "exception in ensure clause"
      end
      assert(false)
    rescue
      assert(true)
    end
    
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
end
