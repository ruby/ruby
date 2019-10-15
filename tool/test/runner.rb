# frozen_string_literal: true
require 'rbconfig'

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require 'test/unit'

require "profile_test_all" if ENV.key?('RUBY_TEST_ALL_PROFILE')
require "tracepointchecker"
require "zombie_hunter"
require "iseq_loader_checker"
require_relative "../test-coverage.rb" if ENV.key?('COVERAGE')

case $0
when __FILE__
  dir = __dir__
when "-e"
  # No default directory
else
  dir = File.expand_path("..", $0)
end
exit Test::Unit::AutoRunner.run(true, dir)
