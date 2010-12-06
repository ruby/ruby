require 'rbconfig'

require 'test/unit'

src_testdir = File.dirname(File.expand_path(__FILE__))
srcdir = File.dirname(src_testdir)

require_relative 'profile_test_all' if ENV['RUBY_TEST_ALL_PROFILE'] == 'true'

tests = Test::Unit.new {|files, options|
  options[:base_directory] = src_testdir
  if files.empty?
    [src_testdir]
  else
    files
  end
}
exit tests.run(ARGV) || true
