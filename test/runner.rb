require 'test/unit/testsuite'
require 'test/unit/testcase'
require 'optparse'

runner = 'console'
opt = OptionParser.new
opt.on("--runner=console", String) do |arg|
  runner = arg
end
opt.parse!(ARGV)

ARGV.each do |tc_name|
  require tc_name
end

class BulkTestSuite < Test::Unit::TestSuite
  def self.suite
    suite = Test::Unit::TestSuite.new
    ObjectSpace.each_object(Class) do |klass|
      suite << klass.suite if (Test::Unit::TestCase > klass)
    end
    suite
  end
end

runners_map = {
  'console' => proc do |suite|
    require 'test/unit/ui/console/testrunner'
    passed = Test::Unit::UI::Console::TestRunner.run(suite).passed?
    exit(passed ? 0 : 1)
  end,
  'gtk' => proc do |suite|
    require 'test/unit/ui/gtk/testrunner'
    Test::Unit::UI::GTK::TestRunner.run(suite)
  end,
  'fox' => proc do |suite|
    require 'test/unit/ui/fox/testrunner'
    Test::Unit::UI::Fox::TestRunner.run(suite)
  end,
}

runners_map[runner].call(BulkTestSuite.suite)
