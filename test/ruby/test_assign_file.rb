require 'test/unit'
require 'tempfile'
require "thread"

class TestAssignFile < Test::Unit::TestCase

  def test_assign
    assert_nothing_raised do
      __FILE__ = 'bob'
    end
  end
  def test_raise
    assert_block do
      eval(<<'EOF', nil, "BOB", 1)
begin
  __FILE__ = "test1"
  def test1
    raise "Error"
  end
  __FILE__ = "test2"
  def test2
    test1
  end
  test2
rescue => x
  assert x.backtrace[0] == "test1:4:in `test1'" && x.backtrace[1] == "test2:8:in `test2'"
  return x.backtrace[0] == "test1:4:in `test1'" && x.backtrace[1] == "test2:8:in `test2'"
end
return false
EOF
    end
  end
  def test_raise_line
    assert_block do
      eval(<<'EOF', nil, "BOB", 1)
begin
  __FILE__ = "test1"
  __LINE__ = 12
  def test1
    raise "Error"
  end
  __FILE__ = "test2"
  def test2
    test1
    __FILE__ = "test2"
  end
  assert __LINE__ == 21
  assert __FILE__ == "test2"
  test2
rescue => x
  assert x.backtrace[0] == "test1:14:in `test1'" && x.backtrace[1] == "test2:18:in `test2'"
  return x.backtrace[0] == "test1:14:in `test1'" && x.backtrace[1] == "test2:18:in `test2'"
end
return false
EOF
    end
  end

  def test_raise_line_block
    assert_block do
      eval(<<'EOF', nil, "test0", 1)
begin
  __FILE__ = "test1"
  __LINE__ = 12
  def test1
    raise "Error"
  end
  __FILE__ = "test2"
  def test2
    test1
    __FILE__ = "test3"
  end
  assert __LINE__ == 21
  assert __FILE__ == "test3"
  test2
rescue => x
  assert x.backtrace[0] == "test1:14:in `test1'" && x.backtrace[1] == "test2:18:in `test2'"
  return x.backtrace[0] == "test1:14:in `test1'" && x.backtrace[1] == "test2:18:in `test2'"
end
return false
EOF
    end
  end

  def test_raise_line_in_block
    assert_block do
      eval(<<'EOF', nil, "test", 1)
begin
  __FILE__ = "test0"
  def test1
    __FILE__ = "test1"
    raise "Error"
  end
  def test2
    __FILE__ = "test2"
    test1
  end
  raise "Error"
rescue => x
  assert x.backtrace[0] == "test2:11:in `block in test_raise_line_in_block'"
end
EOF
    end
  end
end
