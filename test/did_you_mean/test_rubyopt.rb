require_relative './helper'

class DidYouMeanRubyOptTest < Test::Unit::TestCase
  def test_disable_did_you_mean_opt
    assert_in_out_err(%w(--disable-did-you-mean), "p '1'.suc", [], (<<-OUTPUT).split(/\r?\n/))
-:1:in `<main>': undefined method `suc' for "1":String (NoMethodError)
    OUTPUT
  end

  def test_disable_gems_opt
    assert_in_out_err(%w(--disable-gems), "p '1'.suc", [], /Did you mean\?/)
  end
end
