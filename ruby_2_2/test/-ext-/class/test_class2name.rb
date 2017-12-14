require 'test/unit'
require "-test-/class"

class Test_Class < Test::Unit::TestCase
  class Test_Class2Name < superclass
    def test_toplevel_class
      assert_equal("Object", Bug::Class.class2name(::Object))
    end

    def test_toplevel_module
      assert_equal("Kernel", Bug::Class.class2name(::Kernel))
    end

    def test_singleton_class
      assert_equal("Object", Bug::Class.class2name(::Object.new.singleton_class))
    end
  end
end
