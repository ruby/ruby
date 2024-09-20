require_relative 'slow_helper'

class TestSlowV1 < Test::Unit::TestCase
  include TestSlowTimeout
end
