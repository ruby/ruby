ROOT_DIR = File.dirname(__dir__)
$LOAD_PATH.unshift File.join(ROOT_DIR, 'lib') # to use logger in this repo instead of ruby built-in logger
$LOAD_PATH.unshift File.join(ROOT_DIR, 'test', 'lib') # to use custom test-unit in this repo
require 'logger'
require 'test/unit'

begin
  # for standalone test suite on ruby/logger
  require 'core_assertions'

  Test::Unit::TestCase.include Test::Unit::CoreAssertions
rescue LoadError
end
