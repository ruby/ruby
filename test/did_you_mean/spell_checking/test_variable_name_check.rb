require_relative '../helper'

class VariableNameCheckTest < Test::Unit::TestCase
  include DidYouMean::TestHelper

  class User
    def initialize
      @email_address = 'email_address@address.net'
      @first_name    = nil
      @last_name     = nil
    end

    def first_name; end
    def to_s
      "#{@first_name} #{@last_name} <#{email_address}>"
    end

    private

    def cia_codename; "Alexa" end
  end

  module UserModule
    def from_module; end
  end

  def setup
    @user = User.new.extend(UserModule)
  end

  def test_corrections_include_instance_method
    error = assert_raise(NameError) do
      @user.instance_eval { flrst_name }
    end

    @user.instance_eval do
      remove_instance_variable :@first_name
      remove_instance_variable :@last_name
    end

    assert_correction :first_name, error.corrections
    assert_match "Did you mean?  first_name", error.to_s
  end

  def test_corrections_include_method_from_module
    error = assert_raise(NameError) do
      @user.instance_eval { fr0m_module }
    end

    assert_correction :from_module, error.corrections
    assert_match "Did you mean?  from_module", error.to_s
  end

  def test_corrections_include_local_variable_name
    if RUBY_ENGINE != "jruby"
      person = person = nil
      error = (eprson rescue $!) # Do not use @assert_raise here as it changes a scope.

      assert_correction :person, error.corrections
      assert_match "Did you mean?  person", error.to_s
    end
  end

  def test_corrections_include_ruby_predefined_objects
    some_var = some_var = nil

    false_error = assert_raise(NameError) do
      some_var = fals
    end

    true_error = assert_raise(NameError) do
      some_var = treu
    end

    nil_error = assert_raise(NameError) do
      some_var = nul
    end

    file_error = assert_raise(NameError) do
      __FIEL__
    end

    assert_correction :false, false_error.corrections
    assert_match "Did you mean?  false", false_error.to_s

    assert_correction :true, true_error.corrections
    assert_match "Did you mean?  true", true_error.to_s

    assert_correction :nil, nil_error.corrections
    assert_match "Did you mean?  nil", nil_error.to_s

    assert_correction :__FILE__, file_error.corrections
    assert_match "Did you mean?  __FILE__", file_error.to_s
  end

  def test_suggests_yield
    error = assert_raise(NameError) { yeild }

    assert_correction :yield, error.corrections
    assert_match "Did you mean?  yield", error.to_s
  end

  def test_corrections_include_instance_variable_name
    error = assert_raise(NameError){ @user.to_s }

    assert_correction :@email_address, error.corrections
    assert_match "Did you mean?  @email_address", error.to_s
  end

  def test_corrections_include_private_method
    error = assert_raise(NameError) do
      @user.instance_eval { cia_code_name }
    end

    assert_correction :cia_codename, error.corrections
    assert_match "Did you mean?  cia_codename",  error.to_s
  end

  @@does_exist = true

  def test_corrections_include_class_variable_name
    error = assert_raise(NameError){ @@doesnt_exist }

    assert_correction :@@does_exist, error.corrections
    assert_match "Did you mean?  @@does_exist", error.to_s
  end

  def test_struct_name_error
    value = Struct.new(:does_exist).new
    error = assert_raise(NameError){ value[:doesnt_exist] }

    assert_correction [:does_exist, :does_exist=], error.corrections
    assert_match "Did you mean?  does_exist", error.to_s
  end

  def test_exclude_typical_incorrect_suggestions
    error = assert_raise(NameError){ foo }
    assert_empty error.corrections
  end
end
