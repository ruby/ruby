# frozen_string_literal: false
require_relative 'drbtest'

begin
  require 'drb/unix'
rescue LoadError
end

module DRbTests

if Object.const_defined?("UNIXServer")


class DRbUNIXService < DRbService
  %w(ut_drb_drbunix.rb ut_array_drbunix.rb).each do |nm|
    add_service_command(nm)
  end

  def start
    @server = DRb::DRbServer.new('drbunix:', manager, {})
  end
end

class TestDRbUNIXCore < Test::Unit::TestCase
  include DRbCore
  def setup
    @drb_service = DRbUNIXService.new
    super
    setup_service 'ut_drb_drbunix.rb'
  end

  def test_02_unknown
  end

  def test_01_02_loop
  end

  def test_05_eq
  end

  def test_bad_uri
    assert_raise(DRb::DRbBadURI) do
      DRb::DRbServer.new("badfile\n""drbunix:")
    end
  end
end

class TestDRbUNIXAry < Test::Unit::TestCase
  include DRbAry
  def setup
    @drb_service = DRbUNIXService.new
    super
    setup_service 'ut_array_drbunix.rb'
  end
end


end

end
