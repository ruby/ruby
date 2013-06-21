require 'drbtest'

class TestDRbReusePort < Test::Unit::TestCase
  include DRbAry

  def setup
    setup_service 'ut_port.rb'
  end
end

