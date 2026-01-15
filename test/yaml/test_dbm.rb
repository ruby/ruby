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

  def test_each_value
    @dbm["key1"] = "value1"
    @dbm["key2"] = "value2"
    @dbm.each_value do |value|
      assert_match(/value[12]/, value)
    end
  end

  def test_values
    @dbm["key1"] = "value1"
    @dbm["key2"] = "value2"
    @dbm.values.each do |value|
      assert_match(/value[12]/, value)
    end
  end

  def test_shift
    @dbm["key"] = "value"
    assert_equal ["key", "value"], @dbm.shift
  end
end if defined?(YAML::DBM)
