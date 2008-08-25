#!/usr/bin/env ruby

require 'test/unit'
require 'test/unit/assertions'

module Rake
  include Test::Unit::Assertions

  def run_tests(pattern='test/test*.rb', log_enabled=false)
    Dir["#{pattern}"].each { |fn|
      puts fn if log_enabled
      begin
        load fn
      rescue Exception => ex
        puts "Error in #{fn}: #{ex.message}"
        puts ex.backtrace
        assert false
      end
    }
  end

  extend self
end
