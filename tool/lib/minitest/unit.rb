# encoding: utf-8
# frozen_string_literal: true

require "optparse"
require "rbconfig"
require "leakchecker"

##
# Minimal (mostly drop-in) replacement for test-unit.
#
# :include: README.txt

module MiniTest

  def self.const_missing name # :nodoc:
    case name
    when :MINI_DIR then
      msg = "MiniTest::MINI_DIR was removed. Don't violate other's internals."
      warn "WAR\NING: #{msg}"
      warn "WAR\NING: Used by #{caller.first}."
      const_set :MINI_DIR, "bad value"
    else
      super
    end
  end

  ##
  # Assertion base class

  class Assertion < Exception; end

  ##
  # Assertion raised when skipping a test

  class Skip < Assertion; end

  class << self
    ##
    # Filter object for backtraces.

    attr_accessor :backtrace_filter
  end

  class BacktraceFilter # :nodoc:
    def filter bt
      return ["No backtrace"] unless bt

      new_bt = []

      unless $DEBUG then
        bt.each do |line|
          break if line =~ /lib\/minitest/
          new_bt << line
        end

        new_bt = bt.reject { |line| line =~ /lib\/minitest/ } if new_bt.empty?
        new_bt = bt.dup if new_bt.empty?
      else
        new_bt = bt.dup
      end

      new_bt
    end
  end

  self.backtrace_filter = BacktraceFilter.new

  def self.filter_backtrace bt # :nodoc:
    backtrace_filter.filter bt
  end

end # module MiniTest
