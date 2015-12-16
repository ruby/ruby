# frozen_string_literal: false
# $Id$

require 'test/unit'
require 'fileutils'
require_relative 'visibility_tests'

class TestFileUtilsVerbose < Test::Unit::TestCase

  include FileUtils::Verbose
  include TestFileUtils::Visibility

  def setup
    super
    @fu_module = FileUtils::Verbose
  end

end
