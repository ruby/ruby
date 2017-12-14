require 'rbconfig'

src_testdir = File.dirname(File.realpath(__FILE__))
$LOAD_PATH << src_testdir
$LOAD_PATH.unshift "#{src_testdir}/lib"

require 'test/unit'

module Gem
end
class Gem::TestCase < MiniTest::Unit::TestCase
  @@project_dir = File.dirname($LOAD_PATH.last)
end

ENV["GEM_SKIP"] = ENV["GEM_HOME"] = ENV["GEM_PATH"] = "".freeze

require_relative 'lib/profile_test_all' if ENV.has_key?('RUBY_TEST_ALL_PROFILE')
require_relative 'lib/tracepointchecker'

module Test::Unit
  module ZombieHunter
    def after_teardown
      super
      assert_empty(Process.waitall)
    end
  end

  class TestCase
    include ZombieHunter
  end
end

if ENV['COVERAGE']
  $LOAD_PATH.unshift "#{src_testdir}/../coverage/simplecov/lib"
  require 'simplecov'
  SimpleCov.start
end

begin
  exit Test::Unit::AutoRunner.run(true, src_testdir)
rescue NoMemoryError
  system("cat /proc/meminfo") if File.exist?("/proc/meminfo")
  system("ps x -opid,args,%cpu,%mem,nlwp,rss,vsz,wchan,stat,start,time,etime,blocked,caught,ignored,pending,f") if File.exist?("/bin/ps")
  raise
end
