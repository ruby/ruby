# frozen_string_literal: true
require 'test/unit'

module TestRipper; end
class TestRipper::Generic < Test::Unit::TestCase
  SRCDIR = File.expand_path("../../..", __FILE__)

  def assert_parse_files(dir, pattern = "**/*.rb", exclude: nil, gc_stress: GC.stress, test_ratio: nil)
    test_ratio ||= ENV["TEST_RIPPER_RATIO"]&.tap {|s|break s.to_f} || 0.05 # testing all files needs too long time...
    assert_separately(%W[-rripper - #{SRCDIR}/#{dir} #{pattern}],
                      __FILE__, __LINE__, "#{<<-"begin;"}\n#{<<-'end;'}", timeout: Float::INFINITY)
    GC.stress = false
    pattern = "#{pattern}"
    exclude = (
      #{exclude if exclude}
    )
    test_ratio = (
      #{test_ratio}
    )
    gc_stress = (
      #{gc_stress}
    )
    begin;
      class Parser < Ripper
        PARSER_EVENTS.each {|n| eval "def on_#{n}(*args) r = [:#{n}, *args]; r.inspect; Object.new end" }
        SCANNER_EVENTS.each {|n| eval "def on_#{n}(*args) r = [:#{n}, *args]; r.inspect; Object.new end" }
      end
      dir = ARGV.shift
      scripts = Dir.glob(pattern, base: dir)
      scripts.reject! {|script| File.fnmatch?(exclude, script, File::FNM_PATHNAME)} if exclude
      if (1...scripts.size).include?(num = scripts.size * test_ratio)
        scripts = scripts.sample(num)
      end
      scripts.sort!
      for script in scripts
        assert_nothing_raised {
          parser = Parser.new(File.read("#{dir}/#{script}"), script)
          EnvUtil.under_gc_stress(gc_stress) do
            parser.instance_eval "parse", "<#{script}>"
          end
        }
      end
    end;
  end
end
