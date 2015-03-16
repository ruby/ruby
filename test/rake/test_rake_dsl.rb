require File.expand_path('../helper', __FILE__)

class TestRakeDsl < Rake::TestCase

  def setup
    super
    Rake::Task.clear
  end

  def test_namespace_command
    namespace "n" do
      task "t"
    end
    refute_nil Rake::Task["n:t"]
  end

  def test_namespace_command_with_bad_name
    ex = assert_raises(ArgumentError) do
      namespace 1 do end
    end
    assert_match(/string/i, ex.message)
    assert_match(/symbol/i, ex.message)
  end

  def test_namespace_command_with_a_string_like_object
    name = Object.new
    def name.to_str
      "bob"
    end
    namespace name do
      task "t"
    end
    refute_nil Rake::Task["bob:t"]
  end

  def test_no_commands_constant
    assert ! defined?(Commands), "should not define Commands"
  end

end
