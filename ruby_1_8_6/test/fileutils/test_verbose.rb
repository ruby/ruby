# $Id$

require 'test/unit'
require 'fileutils'

class TestFileUtilsVerbose < Test::Unit::TestCase

  include FileUtils::Verbose

  def test_visibility
    FileUtils::METHODS.each do |m|
      assert_equal true, FileUtils::Verbose.respond_to?(m, true),
                   "FileUtils::Verbose.#{m} is not defined"
      assert_equal true, FileUtils::Verbose.respond_to?(m, false),
                   "FileUtils::Verbose.#{m} is not public"
    end
    FileUtils::METHODS.each do |m|
      assert_equal true, respond_to?(m, true),
                   "FileUtils::Verbose.#{m} is not defined"
      assert_equal true, FileUtils::Verbose.private_method_defined?(m),
                   "FileUtils::Verbose.#{m} is not private"
    end
  end

end
