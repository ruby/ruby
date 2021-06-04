require_relative '../helper'

class NameErrorExtensionTest < Test::Unit::TestCase
  SPELL_CHECKERS = DidYouMean::SPELL_CHECKERS

  class TestSpellChecker
    def initialize(*); end
    def corrections; ["does_exist"]; end
  end

  def setup
    @org, SPELL_CHECKERS['NameError'] = SPELL_CHECKERS['NameError'], TestSpellChecker

    @error = assert_raise(NameError){ doesnt_exist }
  end

  def teardown
    SPELL_CHECKERS['NameError'] = @org
  end

  def test_message
    assert_match(/Did you mean\?  does_exist/, @error.to_s)
    assert_match(/Did you mean\?  does_exist/, @error.message)
  end

  def test_to_s_does_not_make_disruptive_changes_to_error_message
    error = assert_raise(NameError) do
      raise NameError, "uninitialized constant Object"
    end

    error.to_s
    assert_equal 1, error.to_s.scan("Did you mean?").count
  end

  def test_correctable_error_objects_are_dumpable
    error =
      begin
        Dir.chdir(__dir__) { File.open('test_name_error_extension.rb') { |f| f.sizee } }
      rescue NoMethodError => e
        e
      end

    error.to_s

    assert_equal "undefined method `sizee' for #<File:test_name_error_extension.rb (closed)>",
                 Marshal.load(Marshal.dump(error)).original_message
  end
end
