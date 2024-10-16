require "test/unit"
require "yaml/dbm"

class TestYAMLDBM < Test::Unit::TestCase
  def setup
    @dbm = YAML::DBM.new("test")
  end

  def teardown
    @dbm.close
    File.unlink("test.db")
  end

  def test_fetch
    @dbm["key"] = "value"
    assert_equal "value", @dbm["key"]
    assert_equal "value", @dbm.fetch("key")
  end

  def test_delete
    @dbm["key"] = "value"
    assert_equal "value", @dbm.delete("key")
    assert_nil @dbm["key"]
  end
end