# frozen_string_literal: false
require 'test/unit'

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

    assert_equal("test2", bar.test2)
    assert_equal("test", bar.test)
    assert_equal("test", foo.test)

    assert_raise(NoMethodError) {foo.test2}

    assert_equal([M003, M002, M001], M003.ancestors)
  end

  def test_user_flags
    assert_separately([], <<-EOS)
      #
      class Array
        undef initialize_copy
        def initialize_copy(*); end
      end
      x = [1, 2, 3].clone
      assert_equal [], x, '[Bug #14847]'
    EOS

    assert_separately([], <<-EOS)
      #
      class Array
        undef initialize_copy
        def initialize_copy(*); end
      end
      x = [1,2,3,4,5,6,7][1..-2].clone
      x.push(1,1,1,1,1)
      assert_equal [1, 1, 1, 1, 1], x, '[Bug #14847]'
    EOS

    assert_separately([], <<-EOS)
      #
      class Hash
        undef initialize_copy
        def initialize_copy(*); end
      end
      h = {}
      h.default_proc = proc { raise }
      h = h.clone
      assert_equal nil, h[:not_exist], '[Bug #14847]'
    EOS
  end
end
