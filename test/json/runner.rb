#!/usr/bin/env ruby

require 'test/unit/ui/console/testrunner'
require 'test/unit/testsuite'
$:.unshift File.expand_path(File.dirname($0))
$:.unshift 'tests'
require 'test_json'
require 'test_json_generate'
require 'test_json_unicode'
require 'test_json_addition'
require 'test_json_rails'
require 'test_json_fixtures'

class TS_AllTests
  def self.suite
    suite = Test::Unit::TestSuite.new name
    suite << TC_JSONGenerate.suite
    suite << TC_JSON.suite
    suite << TC_JSONUnicode.suite
    suite << TC_JSONAddition.suite
    suite << TC_JSONRails.suite
    suite << TC_JSONFixtures.suite
  end
end
Test::Unit::UI::Console::TestRunner.run(TS_AllTests)
