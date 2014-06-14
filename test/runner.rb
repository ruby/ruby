require 'rbconfig'

src_testdir = File.dirname(File.realpath(__FILE__))
$LOAD_PATH << src_testdir
$LOAD_PATH.unshift "#{src_testdir}/lib"

require 'test/unit'
require_relative 'ruby/envutil'

module Gem
end
class Gem::TestCase < MiniTest::Unit::TestCase
  @@project_dir = File.dirname($LOAD_PATH.last)
end

ENV["GEM_SKIP"] = ENV["GEM_HOME"] = ENV["GEM_PATH"] = "".freeze

require_relative 'profile_test_all' if ENV.has_key?('RUBY_TEST_ALL_PROFILE')

module Test::Unit
  module ZombieHunter
    @@zombie_traces = Hash.new(0)

    def after_teardown
      super
      assert_empty(Process.waitall)

      # detect zombie traces.
      TracePoint.stat.each{|key, (activated, deleted)|
        old, @@zombie_traces[key] = @@zombie_traces[key], activated
        assert_equal(old, activated, "The number of active trace events (#{key}) should not increase")
        # puts "TracePoint - deleted: #{deleted}" if deleted > 0
      }
    end
  end
  class TestCase
    include ZombieHunter
  end
end

begin
  exit Test::Unit::AutoRunner.run(true, src_testdir)
rescue NoMemoryError
  system("cat /proc/meminfo") if File.exist?("/proc/meminfo")
  system("ps x -opid,args,%cpu,%mem,nlwp,rss,vsz,wchan,stat,start,time,etime,blocked,caught,ignored,pending,f") if File.exist?("/bin/ps")
  raise
end
