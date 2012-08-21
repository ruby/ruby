begin
  require 'ripper'
  require 'find'
  require 'stringio'
  require 'test/unit'
  ripper_test = true
  module TestRipper; end
rescue LoadError
end

class TestRipper::Generic < Test::Unit::TestCase
  SRCDIR = File.dirname(File.dirname(File.dirname(File.expand_path(__FILE__))))

  class Parser < Ripper
    PARSER_EVENTS.each {|n| eval "def on_#{n}(*args) r = [:#{n}, *args]; r.inspect; Object.new end" }
    SCANNER_EVENTS.each {|n| eval "def on_#{n}(*args) r = [:#{n}, *args]; r.inspect; Object.new end" }
  end

  TEST_RATIO = 0.05 # testing all files needs too long time...

  def capture_stderr
    err = StringIO.new
    begin
      old = $stderr
      $stderr = err
      yield
    ensure
      $stderr = old
    end
    if TEST_RATIO == 1.0
      puts err.string
    end
  end

  def test_parse_files
    Find.find("#{SRCDIR}/lib", "#{SRCDIR}/ext", "#{SRCDIR}/sample", "#{SRCDIR}/test") {|n|
      next if /\.rb\z/ !~ n || !File.file?(n)
      next if TEST_RATIO < rand
      assert_nothing_raised("ripper failed to parse: #{n.inspect}") {
	capture_stderr {
	  Parser.new(File.read(n)).parse
	}
      }
    }
  end
end if ripper_test
