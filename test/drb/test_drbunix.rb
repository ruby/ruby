require 'drbtest'

begin
  require 'drb/unix'
rescue LoadError
end

if Object.const_defined?("UNIXServer")


class DRbUNIXService < DRbService
  %w(ut_drb_drbunix.rb ut_array_drbunix.rb).each do |nm|
    DRb::ExtServManager.command[nm] = "#{@@ruby} #{@@dir}/#{nm}"
  end

  uri = ARGV.shift if $0 == __FILE__
  @server = DRb::DRbServer.new(uri || 'drbunix:', @@manager, {})
end

class TestDRbUNIXCore < Test::Unit::TestCase
  include DRbCore
  def setup
    @ext = DRbUNIXService.manager.service('ut_drb_drbunix.rb')
    @there = @ext.front
  end

  def test_02_unknown
  end

  def test_01_02_loop
  end

  def test_05_eq
  end

  def test_06_timeout
    ten = Onecky.new(3)
    assert_raises(TimeoutError) do
      @there.do_timeout(ten)
    end
    assert_raises(TimeoutError) do
      @there.do_timeout(ten)
    end
    sleep 3
  end
end

class TestDRbUNIXAry < Test::Unit::TestCase
  include DRbAry
  def setup
    @ext = DRbUNIXService.manager.service('ut_array_drbunix.rb')
    @there = @ext.front
  end
end


end
