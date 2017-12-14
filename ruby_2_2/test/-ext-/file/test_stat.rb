require 'test/unit'
require "-test-/file"

class Test_FileStat < Test::Unit::TestCase
  def test_stat_for_fd
    st = open(__FILE__) {|f| Bug::File::Stat.for_fd(f.fileno)}
    assert_equal(File.stat(__FILE__), st)
  end

  def test_stat_for_path
    st = Bug::File::Stat.for_path(__FILE__)
    assert_equal(File.stat(__FILE__), st)
  end
end
