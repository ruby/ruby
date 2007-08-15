# $Id: test_dryrun.rb,v 1.1.2.1 2005/09/23 23:39:01 aamine Exp $

require 'test/unit'
require 'fileutils'

class TestFileUtilsDryRun < Test::Unit::TestCase

  include FileUtils::DryRun

  def test_visibility
    FileUtils::METHODS.each do |m|
      assert_equal true, FileUtils::DryRun.respond_to?(m, true),
                   "FileUtils::DryRun.#{m} not defined"
      assert_equal true, FileUtils::DryRun.respond_to?(m, false),
                   "FileUtils::DryRun.#{m} not public"
    end
    FileUtils::METHODS.each do |m|
      assert_equal true, respond_to?(m, true)
                   "FileUtils::DryRun\##{m} is not defined"
      assert_equal true, FileUtils::DryRun.private_method_defined?(m),
                   "FileUtils::DryRun\##{m} is not private"
    end
  end

end
