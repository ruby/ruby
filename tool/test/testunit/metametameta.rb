# encoding: utf-8
# frozen_string_literal: false

require 'tempfile'
require 'stringio'

class Test::Unit::TestCase
  def clean s
    s.gsub(/^ {6}/, '')
  end
end

class MetaMetaMetaTestCase < Test::Unit::TestCase
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
    Test::Unit::TestCase.reset
    @tu = Test::Unit::Runner.new

    Test::Unit::Runner.runner = nil # protect the outer runner from the inner tests
  end

  def teardown
    super
  end

  def with_output
    synchronize do
      begin
        save = Test::Unit::Runner.output
        @output = StringIO.new("")
        Test::Unit::Runner.output = @output

        yield
      ensure
        Test::Unit::Runner.output = save
      end
    end
  end
end
