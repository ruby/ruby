require 'test_drb'

class TestService
  @@scripts = %w(ut_drb_drbunix.rb ut_array_drbunix.rb)
end

class DRbXCoreTest < DRbCoreTest
  def setup
    @ext = $manager.service('ut_drb_drbunix.rb')
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
    assert_exception(TimeoutError) do
      @there.do_timeout(ten)
    end
    assert_exception(TimeoutError) do
      @there.do_timeout(ten)
    end
    sleep 3
  end
end

class DRbXAryTest < DRbAryTest
  def setup
    @ext = $manager.service('ut_array_drbunix.rb')
    @there = @ext.front
  end
end

if __FILE__ == $0
  $testservice = TestService.new(ARGV.shift || 'drbunix:')
  $manager = $testservice.manager
  RUNIT::CUI::TestRunner.run(DRbXCoreTest.suite)
  RUNIT::CUI::TestRunner.run(DRbXAryTest.suite)
end
