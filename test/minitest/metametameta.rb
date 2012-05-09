# encoding: utf-8
######################################################################
# This file is imported from the minitest project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis.
######################################################################

require 'tempfile'
require 'stringio'
require 'minitest/autorun'

class MetaMetaMetaTestCase < MiniTest::Unit::TestCase
  def assert_report expected = nil
    expected ||= <<-EOM.gsub(/^ {6}/, '')
      Run options: --seed 42

      # Running tests:

      .

      Finished tests in 0.00

      1 tests, 1 assertions, 0 failures, 0 errors, 0 skips
    EOM

    output = @output.string.dup
    output.sub!(/Finished tests in .*/, "Finished tests in 0.00")
    output.sub!(/Loaded suite .*/, 'Loaded suite blah')

    if windows? then
      output.gsub!(/\[(?:[A-Za-z]:)?[^\]:]+:\d+\]/, '[FILE:LINE]')
      output.gsub!(/^(\s+)(?:[A-Za-z]:)?[^:]+:\d+:in/, '\1FILE:LINE:in')
    else
      output.gsub!(/\[[^\]:]+:\d+\]/, '[FILE:LINE]')
      output.gsub!(/^(\s+)[^:]+:\d+:in/, '\1FILE:LINE:in')
    end

    assert_equal(expected, output)
  end

  def setup
    super
    srand 42
    MiniTest::Unit::TestCase.reset
    @tu = MiniTest::Unit.new
    @output = StringIO.new("")
    MiniTest::Unit.runner = nil # protect the outer runner from the inner tests
    MiniTest::Unit.output = @output
  end

  def teardown
    super
    MiniTest::Unit.output = $stdout
    Object.send :remove_const, :ATestCase if defined? ATestCase
  end
end
