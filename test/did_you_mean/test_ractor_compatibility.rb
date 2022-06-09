require_relative './helper'

return if not DidYouMean::TestHelper.ractor_compatible?

class RactorCompatibilityTest < Test::Unit::TestCase
  def test_class_name_suggestion_works_in_ractor
    assert_ractor(<<~CODE, require_relative: "helper")
      class ::Book; end
      include DidYouMean::TestHelper
      error = Ractor.new {
                begin
                  Boook
                rescue NameError => e
                  e.corrections # It is important to call the #corrections method within Ractor.
                  e
                end
              }.take

      assert_correction "Book", error.corrections
    CODE
  end

  def test_key_name_suggestion_works_in_ractor
    assert_ractor(<<~CODE, require_relative: "helper")
      include DidYouMean::TestHelper
      error = Ractor.new {
                begin
                  hash = { "foo" => 1, bar: 2 }

                  hash.fetch(:bax)
                rescue KeyError => e
                  e.corrections # It is important to call the #corrections method within Ractor.
                  e
                end
              }.take

      assert_correction ":bar", error.corrections
      assert_match "Did you mean?  :bar", get_message(error)
    CODE
  end

  def test_method_name_suggestion_works_in_ractor
    assert_ractor(<<~CODE, require_relative: "helper")
      include DidYouMean::TestHelper
      error = Ractor.new {
                begin
                  self.to__s
                rescue NoMethodError => e
                  e.corrections # It is important to call the #corrections method within Ractor.
                  e
                end
              }.take

      assert_correction :to_s, error.corrections
      assert_match "Did you mean?  to_s",  get_message(error)
    CODE
  end

  if defined?(::NoMatchingPatternKeyError)
    def test_pattern_key_name_suggestion_works_in_ractor
      assert_ractor(<<~CODE, require_relative: "helper")
        include DidYouMean::TestHelper
        error = Ractor.new {
                  begin
                    eval(<<~RUBY, binding, __FILE__, __LINE__)
                            hash = {foo: 1, bar: 2, baz: 3}
                            hash => {fooo:}
                            fooo = 1 # suppress "unused variable: fooo" warning
                    RUBY
                  rescue NoMatchingPatternKeyError => e
                    e.corrections # It is important to call the #corrections method within Ractor.
                    e
                  end
                }.take

        assert_correction ":foo", error.corrections
        assert_match "Did you mean?  :foo", get_message(error)
      CODE
    end
  end

  def test_can_raise_other_name_error_in_ractor
    assert_ractor(<<~CODE, require_relative: "helper")
      class FirstNameError < NameError; end
      include DidYouMean::TestHelper
      error = Ractor.new {
        begin
          raise FirstNameError, "Other name error"
        rescue FirstNameError => e
          e.corrections # It is important to call the #corrections method within Ractor.
          e
        end
      }.take

      assert_not_match(/Did you mean\?/, error.message)
    CODE
  end

  def test_variable_name_suggestion_works_in_ractor
    assert_ractor(<<~CODE, require_relative: "helper")
      include DidYouMean::TestHelper
      error = Ractor.new {
        in_ractor = in_ractor = 1

        begin
          in_reactor
        rescue NameError => e
          e.corrections # It is important to call the #corrections method within Ractor.
          e
        end
      }.take

      assert_correction :in_ractor, error.corrections
      assert_match "Did you mean?  in_ractor", get_message(error)
    CODE
  end
end
