require 'test/unit'
require "-test-/st/update"

class Bug::StTable
  class Test_Update < Test::Unit::TestCase
    def setup
      @tbl = Bug::StTable.new
      @tbl[:a] = 1
      @tbl[:b] = 2
    end

    def test_notfound
      assert_equal(false, @tbl.st_update(:c) {42})
      assert_equal({a: 1, b: 2, c: 42}, @tbl)
    end

    def test_continue
      args = nil
      assert_equal(true, @tbl.st_update(:a) {|*x| args = x; false})
      assert_equal({a: 1, b: 2}, @tbl, :a)
      assert_equal([:a, 1], args)
    end

    def test_delete
      args = nil
      assert_equal(true, @tbl.st_update(:a) {|*x| args = x; nil})
      assert_equal({b: 2}, @tbl, :a)
      assert_equal([:a, 1], args)
    end

    def test_update
      args = nil
      assert_equal(true, @tbl.st_update(:a) {|*x| args = x; 3})
      assert_equal({a: 3, b: 2}, @tbl, :a)
      assert_equal([:a, 1], args)
    end

    def test_pass_objects_in_st_table
      bug7330 = '[ruby-core:49220]'
      key = "abc".freeze
      value = "def"
      @tbl[key] = value
      @tbl.st_update("abc") {|*args|
        assert_same(key, args[0], bug7330)
        assert_same(value, args[1], bug7330)
        nil
      }
    end
  end
end
