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
  require 'objspace'
  h = {}
  exit Test::Unit::AutoRunner.run(true, src_testdir)
rescue NoMemoryError
  ObjectSpace.count_objects(h)
  p h
  ObjectSpace.count_objects_size(h)
  p h
  raise
end
