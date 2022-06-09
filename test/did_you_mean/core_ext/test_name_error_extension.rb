require_relative '../helper'

class NameErrorExtensionTest < Test::Unit::TestCase
  include DidYouMean::TestHelper

  SPELL_CHECKERS = DidYouMean.spell_checkers

  class TestSpellChecker
    def initialize(*); end
    def corrections; ["does_exist"]; end
  end

  def setup
    @original_spell_checker = DidYouMean.spell_checkers['NameError']
    DidYouMean.correct_error(NameError, TestSpellChecker)

    @error = assert_raise(NameError){ doesnt_exist }
  end

  def teardown
    DidYouMean.correct_error(NameError, @original_spell_checker)
  end

  def test_message
    if Exception.method_defined?(:detailed_message)
      assert_match(/Did you mean\?  does_exist/, @error.detailed_message)
    else
      assert_match(/Did you mean\?  does_exist/, @error.to_s)
      assert_match(/Did you mean\?  does_exist/, @error.message)
    end
  end

  def test_to_s_does_not_make_disruptive_changes_to_error_message
    error = assert_raise(NameError) do
      raise NameError, "uninitialized constant Object"
    end

    get_message(error)
    assert_equal 1, get_message(error).scan("Did you mean?").count
  end

  def test_correctable_error_objects_are_dumpable
    error =
      begin
        Dir.chdir(__dir__) { File.open('test_name_error_extension.rb') { |f| f.sizee } }
      rescue NoMethodError => e
        e
      end

    get_message(error)

    assert_equal "undefined method `sizee' for #<File:test_name_error_extension.rb (closed)>",
                 Marshal.load(Marshal.dump(error)).original_message
  end
end
