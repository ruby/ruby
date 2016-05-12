# frozen_string_literal: false
require 'drbtest'

module DRbTests

class TestDRbReusePort < Test::Unit::TestCase
  include DRbAry

  def setup
    setup_service 'ut_port.rb'
  end
end

end
