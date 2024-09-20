# frozen_string_literal: true
# $Id$

require 'fileutils'
require 'test/unit'
require_relative 'visibility_tests'

class TestFileUtilsDryRun < Test::Unit::TestCase

  include FileUtils::DryRun
  include TestFileUtilsIncVisibility

  def setup
    super
    @fu_module = FileUtils::DryRun
  end

end
