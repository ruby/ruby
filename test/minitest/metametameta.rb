# encoding: utf-8
######################################################################
# This file is imported from the minitest project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis.
######################################################################

require 'tempfile'
require 'stringio'
require 'minitest/autorun'

class MiniTest::Unit::TestCase
  def clean s
    s.gsub(/^ {6}/, '')
  end
end

class MetaMetaMetaTestCase < MiniTest::Unit::TestCase
  def assert_report expected, flags = %w[--seed 42]
    header = clean <<-EOM
      Run options: #{flags.map { |s| s =~ /\|/ ? s.inspect : s }.join " "}

      # Running tests:

    EOM

    with_output do
      @tu.run flags
    end

    output = @output.string.dup
    output.sub!(/Finished tests in .*/, "Finished tests in 0.00")
    output.sub!(/Loaded suite .*/, 'Loaded suite blah')

    output.gsub!(/ = \d+.\d\d s = /, ' = 0.00 s = ')
    output.gsub!(/0x[A-Fa-f0-9]+/, '0xXXX')

    if windows? then
      output.gsub!(/\[(?:[A-Za-z]:)?[^\]:]+:\d+\]/, '[FILE:LINE]')
      output.gsub!(/^(\s+)(?:[A-Za-z]:)?[^:]+:\d+:in/, '\1FILE:LINE:in')
    else
      output.gsub!(/\[[^\]:]+:\d+\]/, '[FILE:LINE]')
      output.gsub!(/^(\s+)[^:]+:\d+:in/, '\1FILE:LINE:in')
    end

    assert_equal header + expected, output
  end

  def setup
    super
    srand 42
    MiniTest::Unit::TestCase.reset
    @tu = MiniTest::Unit.new

    MiniTest::Unit.runner = nil # protect the outer runner from the inner tests
  end

  def teardown
    super
  end

  def with_output
    synchronize do
      begin
        @output = StringIO.new("")
        MiniTest::Unit.output = @output

        yield
      ensure
        MiniTest::Unit.output = STDOUT
      end
    end
  end
end
