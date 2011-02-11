require 'rbconfig'

require 'test/unit'

src_testdir = File.dirname(File.expand_path(__FILE__))
srcdir = File.dirname(src_testdir)

require_relative 'profile_test_all' if ENV['RUBY_TEST_ALL_PROFILE'] == 'true'

exit Test::Unit::AutoRunner.run(true, src_testdir)
