require 'test/unit'

$KCODE = 'none'

class TestClone < Test::Unit::TestCase
  module M001; end
  module M002; end
  module M003; include M002; end
  module M002; include M001; end
  module M003; include M002; end
    
  def test_clone
    foo = Object.new
    def foo.test
      "test"
    end
    bar = foo.clone
    def bar.test2
      "test2"
    end
    
    assert(bar.test2 == "test2")
    assert(bar.test == "test")
    assert(foo.test == "test")  
    
    begin
      foo.test2
      assert false
    rescue NoMethodError
      assert true
    end
    
    assert(M003.ancestors == [M003, M002, M001])
  end
end
