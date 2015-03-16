# $Id$

require 'fileutils'
require 'test/unit'
require_relative 'visibility_tests'

class TestFileUtilsDryRun < Test::Unit::TestCase

  include FileUtils::DryRun
  include TestFileUtils::Visibility

  def setup
    super
    @fu_module = FileUtils::DryRun
  end

end
