require 'rbconfig'

require 'test/unit'

src_testdir = File.dirname(File.realpath(__FILE__))
$LOAD_PATH << src_testdir
module Gem
end
class Gem::TestCase < MiniTest::Unit::TestCase
  @@project_dir = File.dirname($LOAD_PATH.last)
end

ENV["GEM_SKIP"] = ENV["GEM_HOME"] = ENV["GEM_PATH"] = "".freeze

require_relative 'profile_test_all' if ENV['RUBY_TEST_ALL_PROFILE'] == 'true'

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

begin
  exit Test::Unit::AutoRunner.run(true, src_testdir)
rescue NoMemoryError
  system("cat /proc/meminfo") if File.exist?("/proc/meminfo")
  system("ps x -opid,args,%cpu,%mem,nlwp,rss,vsz,wchan,stat,start,time,etime,blocked,caught,ignored,pending,f") if File.exist?("/bin/ps")
  raise
end
