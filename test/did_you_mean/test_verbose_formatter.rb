require_relative './helper'

class VerboseFormatterTest < Test::Unit::TestCase
  def setup
    require_relative File.join(DidYouMean::TestHelper.root, 'verbose')

    DidYouMean.formatter = DidYouMean::VerboseFormatter.new
  end

  def teardown
    DidYouMean.formatter = DidYouMean::PlainFormatter.new
  end

  def test_message
    @error = assert_raise(NoMethodError){ 1.zeor? }

    assert_match <<~MESSAGE.strip, @error.message
      undefined method `zeor?' for 1:Integer

          Did you mean? zero?
    MESSAGE
  end
end
