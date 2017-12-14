#
# purpose:
#  Profile memory usage of each tests.
#
# usage:
#   RUBY_TEST_ALL_PROFILE=[file] make test-all
#
# output:
#   [file] specified by RUBY_TEST_ALL_PROFILE
#   If [file] is 'true', then it is ./test_all_profile
#
# collected information:
#   - ObjectSpace.memsize_of_all
#   - GC.stat
#   - /proc/meminfo     (some fields, if exists)
#   - /proc/self/status (some fields, if exists)
#   - /proc/self/statm  (if exists)
#

require 'objspace'

class MiniTest::Unit::TestCase
  alias orig_run run

  file = ENV['RUBY_TEST_ALL_PROFILE']
  file = 'test-all-profile-result' if file == 'true'
  TEST_ALL_PROFILE_OUT = open(file, 'w')
  TEST_ALL_PROFILE_GC_STAT_HASH = {}
  TEST_ALL_PROFILE_BANNER = ['name']
  TEST_ALL_PROFILE_PROCS  = []

  def self.add *name, &b
    TEST_ALL_PROFILE_BANNER.concat name
    TEST_ALL_PROFILE_PROCS << b
  end

  add 'failed?' do |result, tc|
    result << (tc.passed? ? 0 : 1)
  end

  add 'memsize_of_all' do |result, *|
    result << ObjectSpace.memsize_of_all
  end

  add *GC.stat.keys do |result, *|
    GC.stat(TEST_ALL_PROFILE_GC_STAT_HASH)
    result.concat TEST_ALL_PROFILE_GC_STAT_HASH.values
  end

  def self.add_proc_meminfo file, fields
    return unless FileTest.exist?(file)
    regexp = /(#{fields.join("|")}):\s*(\d+) kB/
    # check = {}; fields.each{|e| check[e] = true}
    add *fields do |result, *|
      text = File.read(file)
      text.scan(regexp){
        # check.delete $1
        result << $2
        ''
      }
      # raise check.inspect unless check.empty?
    end
  end

  add_proc_meminfo '/proc/meminfo', %w(MemTotal MemFree)
  add_proc_meminfo '/proc/self/status', %w(VmPeak VmSize VmHWM VmRSS)

  if FileTest.exist?('/proc/self/statm')
    add *%w(size resident share text lib data dt) do |result, *|
      result.concat File.read('/proc/self/statm').split(/\s+/)
    end
  end

  def memprofile_test_all_result_result
    result = ["#{self.class}\##{self.__name__.to_s.gsub(/\s+/, '')}"]
    TEST_ALL_PROFILE_PROCS.each{|proc|
      proc.call(result, self)
    }
    result.join("\t")
  end

  def run runner
    result = orig_run(runner)
    TEST_ALL_PROFILE_OUT.puts memprofile_test_all_result_result
    TEST_ALL_PROFILE_OUT.flush
    result
  end

  TEST_ALL_PROFILE_OUT.puts TEST_ALL_PROFILE_BANNER.join("\t")
end
