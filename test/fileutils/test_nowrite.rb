# frozen_string_literal: true
# $Id$

require 'fileutils'
require 'test/unit'
require_relative 'visibility_tests'

class TestFileUtilsNoWrite < Test::Unit::TestCase

  include FileUtils::NoWrite
  include TestFileUtilsInc::Visibility

  def setup
    super
    @fu_module = FileUtils::NoWrite
  end

end
