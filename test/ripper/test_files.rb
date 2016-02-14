require 'test/unit'

module TestRipper; end
class TestRipper::Generic < Test::Unit::TestCase
  def test_parse_files
    srcdir = File.expand_path("../../..", __FILE__)
    assert_separately(%W[--disable-gem -rripper - #{srcdir}],
                      __FILE__, __LINE__, <<-'eom', timeout: Float::INFINITY)
      TEST_RATIO = (ENV["TEST_RIPPER_RATIO"].nil? ? 0.05 : ENV["TEST_RIPPER_RATIO"].to_f) # testing all files needs too long time...
      class Parser < Ripper
        PARSER_EVENTS.each {|n| eval "def on_#{n}(*args) r = [:#{n}, *args]; r.inspect; Object.new end" }
        SCANNER_EVENTS.each {|n| eval "def on_#{n}(*args) r = [:#{n}, *args]; r.inspect; Object.new end" }
      end
      dir = ARGV.shift
      for script in Dir["#{dir}/{lib,sample,ext,test}/**/*.rb"].sort
        next if TEST_RATIO and TEST_RATIO < rand
        assert_nothing_raised("ripper failed to parse: #{script.inspect}") {
          Parser.new(File.read(script), script).parse
        }
      end
    eom
  end
end
