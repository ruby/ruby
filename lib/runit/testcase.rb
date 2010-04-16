# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'runit/testresult'
require 'runit/testsuite'
require 'runit/assert'
require 'runit/error'
require 'test/unit/testcase'

module RUNIT
  class TestCase < Test::Unit::TestCase
    include RUNIT::Assert

    def self.suite
      method_names = instance_methods(true)
      tests = method_names.delete_if { |method_name| method_name !~ /^test/ }
      suite = TestSuite.new(name)
      tests.each {
        |test|
        catch(:invalid_test) {
          suite << new(test, name)
        }
      }
      return suite
    end

    def initialize(test_name, suite_name=self.class.name)
      super(test_name)
    end

    def assert_equals(*args)
      assert_equal(*args)
    end

    def name
      super.sub(/^(.*?)\((.*)\)$/, '\2#\1')
    end

    def run(result, &progress_block)
      progress_block = proc {} unless (block_given?)
      super(result, &progress_block)
    end
  end
end
