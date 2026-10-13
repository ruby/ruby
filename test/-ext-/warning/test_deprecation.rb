# frozen_string_literal: false
require 'test/unit'
require '-test-/warning'

class Test_Warning_Deprecation < Test::Unit::TestCase
  MESSAGE = /\A#{Regexp.quote(__FILE__)}:\d+: warning: foo is deprecated and will be removed in Ruby 9\.9\n\z/

  def capture(deprecated: nil, verbose: true)
    EnvUtil.verbose_warning do
      $VERBOSE = verbose
      Warning[:deprecated] = deprecated unless deprecated.nil?
      yield
    end
  end

  def test_to_remove
    assert_match(MESSAGE, capture(deprecated: false) {Bug::Warning.to_remove("foo", nil)})
    assert_match(MESSAGE, capture(deprecated: true) {Bug::Warning.to_remove("foo", nil)})
    assert_equal("", capture(verbose: nil) {Bug::Warning.to_remove("foo", nil)})
    assert_match(/removed in Ruby 9\.9; use bar instead\n\z/,
                 capture(deprecated: false) {Bug::Warning.to_remove("foo", "bar")})
  end

  def test_deprecated_to_remove
    assert_equal("", capture(deprecated: false) {Bug::Warning.deprecated_to_remove("foo", nil)})
    assert_match(MESSAGE, capture(deprecated: true) {Bug::Warning.deprecated_to_remove("foo", nil)})
  end

  def test_scheduled_deprecation
    assert_equal("", capture(deprecated: false) {Bug::Warning.scheduled_before("foo")})
    assert_match(MESSAGE, capture(deprecated: true) {Bug::Warning.scheduled_before("foo")})
    assert_match(MESSAGE, capture(deprecated: false) {Bug::Warning.scheduled_reached("foo")})
    assert_equal("", capture(verbose: nil) {Bug::Warning.scheduled_reached("foo")})
  end
end
