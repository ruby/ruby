begin

require 'ripper'
require 'find'
require 'test/unit'

class TestRipper_Generic < Test::Unit::TestCase
  SRCDIR = File.dirname(File.dirname(File.dirname(File.expand_path(__FILE__))))

  class Parser < Ripper
    PARSER_EVENTS.each {|n| eval "def on_#{n}(*args) r = [:#{n}, *args]; r.inspect; Object.new end" }
    SCANNER_EVENTS.each {|n| eval "def on_#{n}(*args) r = [:#{n}, *args]; r.inspect; Object.new end" }
  end

  def test_parse_files
    Find.find("#{SRCDIR}/lib", "#{SRCDIR}/ext", "#{SRCDIR}/sample", "#{SRCDIR}/test") {|n|
      next if /\.rb\z/ !~ n || !File.file?(n)
      assert_nothing_raised("ripper failed to parse: #{n.inspect}") { Parser.new(File.read(n)).parse }
    }
  end
end

rescue LoadError
end

