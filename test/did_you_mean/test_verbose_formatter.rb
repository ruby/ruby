require_relative './helper'

class VerboseFormatterTest < Test::Unit::TestCase
  class ErrorHighlightDummyFormatter
    def message_for(spot)
      ""
    end
  end

  def setup
    require_relative File.join(DidYouMean::TestHelper.root, 'verbose')

    DidYouMean.formatter = DidYouMean::VerboseFormatter.new

    if defined?(ErrorHighlight)
      @error_highlight_old_formatter = ErrorHighlight.formatter
      ErrorHighlight.formatter = ErrorHighlightDummyFormatter.new
    end
  end

  def teardown
    DidYouMean.formatter = DidYouMean::PlainFormatter.new

    if defined?(ErrorHighlight)
      ErrorHighlight.formatter = @error_highlight_old_formatter
    end
  end

  def test_message
    @error = assert_raise(NoMethodError){ 1.zeor? }

    assert_match <<~MESSAGE.strip, @error.message
      undefined method `zeor?' for 1:Integer

          Did you mean? zero?
    MESSAGE
  end
end
