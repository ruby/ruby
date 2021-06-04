# frozen_string_literal: true

module GCCompactChecker
  def after_teardown
    super
    GC.compact
  end
end

Test::Unit::TestCase.include GCCompactChecker if ENV['RUBY_TEST_GC_COMPACT']
