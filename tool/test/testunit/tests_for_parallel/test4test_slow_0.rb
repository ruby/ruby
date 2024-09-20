require_relative 'slow_helper'

class TestSlowV0 < Test::Unit::TestCase
  include TestSlowTimeout
end
