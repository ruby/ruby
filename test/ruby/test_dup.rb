# frozen_string_literal: false
require 'test/unit'

class TestDup < Test::Unit::TestCase
  module M001; end
  module M002; end
  module M003; include M002; end
  module M002; include M001; end
  module M003; include M002; end

  def test_dup
    foo = Object.new
    def foo.test
      "test"
    end
    bar = foo.dup
    def bar.test2
      "test2"
    end

    assert_equal("test2", bar.test2)
    assert_raise(NoMethodError) { bar.test }
    assert_equal("test", foo.test)

    assert_raise(NoMethodError) {foo.test2}

    assert_equal([M003, M002, M001], M003.ancestors)
  end

  def test_frozen_properties_not_retained_on_dup
    obj = Object.new.freeze
    duped_obj = obj.dup

    assert_predicate(obj, :frozen?)
    refute_predicate(duped_obj, :frozen?)
  end

  def test_ivar_retained_on_dup
    obj = Object.new
    obj.instance_variable_set(:@a, 1)
    duped_obj = obj.dup

    assert_equal(obj.instance_variable_get(:@a), 1)
    assert_equal(duped_obj.instance_variable_get(:@a), 1)
  end

  def test_ivars_retained_on_extended_obj_dup
    ivars = { :@a => 1, :@b => 2, :@c => 3, :@d => 4 }
    obj = Object.new
    ivars.each do |ivar_name, val|
      obj.instance_variable_set(ivar_name, val)
    end

    duped_obj = obj.dup

    ivars.each do |ivar_name, val|
      assert_equal(obj.instance_variable_get(ivar_name), val)
      assert_equal(duped_obj.instance_variable_get(ivar_name), val)
    end
  end

  def test_frozen_properties_not_retained_on_dup_with_ivar
    obj = Object.new
    obj.instance_variable_set(:@a, 1)
    obj.freeze

    duped_obj = obj.dup

    assert_predicate(obj, :frozen?)
    assert_equal(obj.instance_variable_get(:@a), 1)

    refute_predicate(duped_obj, :frozen?)
    assert_equal(duped_obj.instance_variable_get(:@a), 1)
  end

  def test_user_flags
    assert_separately([], <<-EOS)
      #
      class Array
        undef initialize_copy
        def initialize_copy(*); end
      end
      x = [1, 2, 3].dup
      assert_equal [], x, '[Bug #14847]'
    EOS

    assert_separately([], <<-EOS)
      #
      class Array
        undef initialize_copy
        def initialize_copy(*); end
      end
      x = [1,2,3,4,5,6,7][1..-2].dup
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
      h = h.dup
      assert_equal nil, h[:not_exist], '[Bug #14847]'
    EOS
  end
end
