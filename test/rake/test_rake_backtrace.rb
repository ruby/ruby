require File.expand_path('../helper', __FILE__)
require 'open3'

class TestBacktraceSuppression < Rake::TestCase
  def test_bin_rake_suppressed
    paths = ["something/bin/rake:12"]

    actual = Rake::Backtrace.collapse(paths)

    assert_equal [], actual
  end

  def test_system_dir_suppressed
    path = RbConfig::CONFIG['rubylibprefix']
    skip if path.nil?
    path = File.expand_path path

    paths = [path + ":12"]

    actual = Rake::Backtrace.collapse(paths)

    assert_equal [], actual
  end

  def test_near_system_dir_isnt_suppressed
    path = RbConfig::CONFIG['rubylibprefix']
    skip if path.nil?
    path = File.expand_path path

    paths = [" " + path + ":12"]

    actual = Rake::Backtrace.collapse(paths)

    assert_equal paths, actual
  end
end

class TestRakeBacktrace < Rake::TestCase
  include RubyRunner

  def setup
    super

    skip 'tmpdir is suppressed in backtrace' if
      Rake::Backtrace::SUPPRESS_PATTERN =~ Dir.pwd
  end

  def invoke(*args)
    rake(*args)
    @err
  end

  def test_single_collapse
    rakefile %q{
      task :foo do
        raise "foooo!"
      end
    }

    lines = invoke("foo").split("\n")

    assert_equal "rake aborted!", lines[0]
    assert_equal "foooo!", lines[1]
    assert_something_matches %r!\A#{Regexp.quote Dir.pwd}/Rakefile:3!i, lines
    assert_something_matches %r!\ATasks:!, lines
  end

  def test_multi_collapse
    rakefile %q{
      task :foo do
        Rake.application.invoke_task(:bar)
      end
      task :bar do
        raise "barrr!"
      end
    }

    lines = invoke("foo").split("\n")

    assert_equal "rake aborted!", lines[0]
    assert_equal "barrr!", lines[1]
    assert_something_matches %r!\A#{Regexp.quote Dir.pwd}/Rakefile:6!i, lines
    assert_something_matches %r!\A#{Regexp.quote Dir.pwd}/Rakefile:3!i, lines
    assert_something_matches %r!\ATasks:!, lines
  end

  def test_suppress_option
    rakefile %q{
      task :baz do
        raise "bazzz!"
      end
    }

    lines = invoke("baz").split("\n")
    assert_equal "rake aborted!", lines[0]
    assert_equal "bazzz!", lines[1]
    assert_something_matches %r!Rakefile!i, lines

    lines = invoke("--suppress-backtrace", ".ak.file", "baz").split("\n")
    assert_equal "rake aborted!", lines[0]
    assert_equal "bazzz!", lines[1]
    refute_match %r!Rakefile!i, lines[2]
  end

  private

  # Assert that the pattern matches at least one line in +lines+.
  def assert_something_matches(pattern, lines)
    lines.each do |ln|
      if pattern =~ ln
        assert_match pattern, ln
        return
      end
    end
    flunk "expected #{pattern.inspect} to match something in:\n" +
      "#{lines.join("\n    ")}"
  end

end
