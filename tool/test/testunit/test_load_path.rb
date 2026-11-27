# frozen_string_literal: false
require 'test/unit'
require 'optparse'

class TestLoadPathOption < Test::Unit::TestCase
  # Representative absolute paths that never contain the platform's
  # File::PATH_SEPARATOR, so joining them with it round-trips exactly.
  # On Windows the separator is ";", so drive-letter paths (which embed
  # a colon) are the case the old hardcoded split(":") used to break.
  def sample_dirs
    if File::PATH_SEPARATOR == ";"
      ["V:/foo/lib", "C:/bar/lib"]
    else
      ["/foo/lib", "/bar/lib"]
    end
  end

  def build_parser
    base = Class.new do
      def setup_options(parser, options); end
    end
    klass = Class.new(base) do
      prepend Test::Unit::LoadPathOption
    end
    parser = OptionParser.new
    klass.new.setup_options(parser, {})
    parser
  end

  def parse_load_path(argv)
    saved = $LOAD_PATH.dup
    build_parser.parse(argv)
    $LOAD_PATH - saved
  ensure
    $LOAD_PATH.replace(saved)
  end

  def test_single_directory_kept_intact
    dir = sample_dirs.first
    assert_equal([dir], parse_load_path(["-I#{dir}"]),
                 "a single -I directory must be added verbatim")
  end

  def test_multiple_directories_split_on_path_separator
    dirs = sample_dirs
    joined = dirs.join(File::PATH_SEPARATOR)
    # unshift reverses insertion order, so compare as a set.
    assert_equal(dirs.sort, parse_load_path(["-I#{joined}"]).sort,
                 "-I must split only on File::PATH_SEPARATOR")
  end
end
