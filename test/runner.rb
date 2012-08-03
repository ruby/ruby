require 'rbconfig'

require 'test/unit'

src_testdir = File.dirname(File.realpath(__FILE__))
$LOAD_PATH << src_testdir
module Gem
end
class Gem::TestCase < MiniTest::Unit::TestCase
  @@project_dir = File.dirname($LOAD_PATH.last)
end

srcdir = File.dirname(src_testdir)
default_gems = Dir.glob(srcdir + "/{lib,ext}/**/*.gemspec").map {|path| File.basename(path, ".*")}
File.foreach(srcdir + "/defs/default_gems") do |line|
  next if /^\s*#/ =~ line
  default_gems << line[/^\S+/]
end
default_gems |= (ENV["GEM_SKIP"] || '').split(/:/)
ENV["GEM_SKIP"] = default_gems.join(':')
ENV["GEM_HOME"] = ENV["GEM_PATH"] = "".freeze

require_relative 'profile_test_all' if ENV['RUBY_TEST_ALL_PROFILE'] == 'true'

exit Test::Unit::AutoRunner.run(true, src_testdir)
