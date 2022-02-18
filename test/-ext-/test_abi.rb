# frozen_string_literal: true

class TestABI < Test::Unit::TestCase
  def test_require_lib_with_incorrect_abi_on_dev_ruby
    omit "ABI is not checked" unless abi_checking_supported?

    assert_separately [], <<~RUBY
      err = assert_raise(LoadError) { require "-test-/abi" }
      assert_match(/ABI version of binary is incompatible with this Ruby/, err.message)
    RUBY
  end

  def test_disable_abi_check_using_environment_variable
    omit "ABI is not checked" unless abi_checking_supported?

    assert_separately [{ "RUBY_ABI_CHECK" => "0" }], <<~RUBY
      assert_nothing_raised { require "-test-/abi" }
    RUBY
  end

  def test_enable_abi_check_using_environment_variable
    omit "ABI is not checked" unless abi_checking_supported?

    assert_separately [{ "RUBY_ABI_CHECK" => "1" }], <<~RUBY
      err = assert_raise(LoadError) { require "-test-/abi" }
      assert_match(/ABI version of binary is incompatible with this Ruby/, err.message)
    RUBY
  end

  def test_require_lib_with_incorrect_abi_on_release_ruby
    omit "ABI is enforced" if abi_checking_supported?

    assert_separately [], <<~RUBY
      assert_nothing_raised { require "-test-/abi" }
    RUBY
  end

  private

  def abi_checking_supported?
    !(RUBY_PLATFORM =~ /mswin|mingw/)
  end
end
