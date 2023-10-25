# frozen_string_literal: true

require_relative "helper"
require "rubygems/request_set"
require "rubygems/request_set/lockfile"
require "rubygems/request_set/lockfile/tokenizer"
require "rubygems/request_set/lockfile/parser"

class TestGemRequestSetLockfileTokenizer < Gem::TestCase
  def setup
    super

    @gem_deps_file = "gem.deps.rb"
    @lock_file = File.expand_path "#{@gem_deps_file}.lock"
  end

  def test_peek
    tokenizer = Gem::RequestSet::Lockfile::Tokenizer.new "\n"

    assert_equal :newline, tokenizer.peek.first

    assert_equal :newline, tokenizer.next_token.first

    assert_equal :EOF, tokenizer.peek.first
  end

  def test_skip
    tokenizer = Gem::RequestSet::Lockfile::Tokenizer.new "\n"

    refute_predicate tokenizer, :empty?

    tokenizer.skip :newline

    assert_empty tokenizer
  end

  def test_token_pos
    tokenizer = Gem::RequestSet::Lockfile::Tokenizer.new ""
    assert_equal [5, 0], tokenizer.token_pos(5)

    tokenizer = Gem::RequestSet::Lockfile::Tokenizer.new "", nil, 1, 2
    assert_equal [3, 1], tokenizer.token_pos(5)
  end

  def test_tokenize
    write_lockfile <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2)
      b (= 2)
      c (!= 3)
      d (> 4)
      e (< 5)
      f (>= 6)
      g (<= 7)
      h (~> 8)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  a
    LOCKFILE

    expected = [
      [:section,     "GEM",               0,  0],
      [:newline,     nil,                 3,  0],

      [:entry,       "remote",            2,  1],
      [:text,        @gem_repo,           10, 1],
      [:newline,     nil,                 34, 1],

      [:entry,       "specs",             2,  2],
      [:newline,     nil,                 8,  2],

      [:text,        "a",                 4,  3],
      [:l_paren,     nil,                 6,  3],
      [:text,        "2",                 7,  3],
      [:r_paren,     nil,                 8,  3],
      [:newline,     nil,                 9,  3],

      [:text,        "b",                 6,  4],
      [:l_paren,     nil,                 8,  4],
      [:requirement, "=",                 9,  4],
      [:text,        "2",                 11, 4],
      [:r_paren,     nil,                 12, 4],
      [:newline,     nil,                 13, 4],

      [:text,        "c",                 6,  5],
      [:l_paren,     nil,                 8,  5],
      [:requirement, "!=",                9,  5],
      [:text,        "3",                 12, 5],
      [:r_paren,     nil,                 13, 5],
      [:newline,     nil,                 14, 5],

      [:text,        "d",                 6,  6],
      [:l_paren,     nil,                 8,  6],
      [:requirement, ">",                 9,  6],
      [:text,        "4",                 11, 6],
      [:r_paren,     nil,                 12, 6],
      [:newline,     nil,                 13, 6],

      [:text,        "e",                 6,  7],
      [:l_paren,     nil,                 8,  7],
      [:requirement, "<",                 9,  7],
      [:text,        "5",                 11, 7],
      [:r_paren,     nil,                 12, 7],
      [:newline,     nil,                 13, 7],

      [:text,        "f",                 6,  8],
      [:l_paren,     nil,                 8,  8],
      [:requirement, ">=",                9,  8],
      [:text,        "6",                 12, 8],
      [:r_paren,     nil,                 13, 8],
      [:newline,     nil,                 14, 8],

      [:text,        "g",                 6,  9],
      [:l_paren,     nil,                 8,  9],
      [:requirement, "<=",                9,  9],
      [:text,        "7",                 12, 9],
      [:r_paren,     nil,                 13, 9],
      [:newline,     nil,                 14, 9],

      [:text,        "h",                 6,  10],
      [:l_paren,     nil,                 8,  10],
      [:requirement, "~>",                9,  10],
      [:text,        "8",                 12, 10],
      [:r_paren,     nil,                 13, 10],
      [:newline,     nil,                 14, 10],

      [:newline,     nil,                 0,  11],

      [:section,     "PLATFORMS",         0,  12],
      [:newline,     nil,                 9,  12],

      [:text,        Gem::Platform::RUBY, 2,  13],
      [:newline,     nil,                 6,  13],

      [:newline,     nil,                 0,  14],

      [:section,     "DEPENDENCIES",      0,  15],
      [:newline,     nil,                 12, 15],

      [:text,        "a",                 2,  16],
      [:newline,     nil,                 3,  16],
    ]

    assert_equal expected, tokenize_lockfile
  end

  def test_tokenize_capitals
    write_lockfile <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    Ab (2)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  Ab
    LOCKFILE

    expected = [
      [:section, "GEM",               0,  0],
      [:newline, nil,                 3,  0],
      [:entry,   "remote",            2,  1],
      [:text,    @gem_repo,           10, 1],
      [:newline, nil,                 34, 1],
      [:entry,   "specs",             2,  2],
      [:newline, nil,                 8,  2],
      [:text,    "Ab",                4,  3],
      [:l_paren, nil,                 7,  3],
      [:text,    "2",                 8,  3],
      [:r_paren, nil,                 9,  3],
      [:newline, nil,                 10, 3],
      [:newline, nil,                 0,  4],
      [:section, "PLATFORMS",         0,  5],
      [:newline, nil,                 9,  5],
      [:text,    Gem::Platform::RUBY, 2,  6],
      [:newline, nil,                 6,  6],
      [:newline, nil,                 0,  7],
      [:section, "DEPENDENCIES",      0,  8],
      [:newline, nil,                 12, 8],
      [:text,    "Ab",                2,  9],
      [:newline, nil,                 4,  9],
    ]

    assert_equal expected, tokenize_lockfile
  end

  def test_tokenize_conflict_markers
    write_lockfile "<<<<<<<"

    e = assert_raise Gem::RequestSet::Lockfile::ParseError do
      tokenize_lockfile
    end

    assert_equal "your #{@lock_file} contains merge conflict markers (at line 0 column 0)",
                 e.message

    write_lockfile "|||||||"

    e = assert_raise Gem::RequestSet::Lockfile::ParseError do
      tokenize_lockfile
    end

    assert_equal "your #{@lock_file} contains merge conflict markers (at line 0 column 0)",
                 e.message

    write_lockfile "======="

    e = assert_raise Gem::RequestSet::Lockfile::ParseError do
      tokenize_lockfile
    end

    assert_equal "your #{@lock_file} contains merge conflict markers (at line 0 column 0)",
                 e.message

    write_lockfile ">>>>>>>"

    e = assert_raise Gem::RequestSet::Lockfile::ParseError do
      tokenize_lockfile
    end

    assert_equal "your #{@lock_file} contains merge conflict markers (at line 0 column 0)",
                 e.message
  end

  def test_tokenize_git
    write_lockfile <<-LOCKFILE
DEPENDENCIES
  a!
    LOCKFILE

    expected = [
      [:section, "DEPENDENCIES", 0,  0],
      [:newline, nil,            12, 0],

      [:text,    "a",            2,  1],
      [:bang,    nil,            3,  1],
      [:newline, nil,            4,  1],
    ]

    assert_equal expected, tokenize_lockfile
  end

  def test_tokenize_multiple
    write_lockfile <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (2)
      b (~> 3.0, >= 3.0.1)
    LOCKFILE

    expected = [
      [:section,     "GEM",     0,  0],
      [:newline,     nil,       3,  0],

      [:entry,       "remote",  2,  1],
      [:text,        @gem_repo, 10, 1],
      [:newline,     nil,       34, 1],

      [:entry,       "specs",   2,  2],
      [:newline,     nil,       8,  2],

      [:text,        "a",       4,  3],
      [:l_paren,     nil,       6,  3],
      [:text,        "2",       7,  3],
      [:r_paren,     nil,       8,  3],
      [:newline,     nil,       9,  3],

      [:text,        "b",       6,  4],
      [:l_paren,     nil,       8,  4],
      [:requirement, "~>",      9,  4],
      [:text,        "3.0",     12, 4],
      [:comma,       nil,       15, 4],
      [:requirement, ">=",      17, 4],
      [:text,        "3.0.1",   20, 4],
      [:r_paren,     nil,       25, 4],
      [:newline,     nil,       26, 4],
    ]

    assert_equal expected, tokenize_lockfile
  end

  def test_unget
    tokenizer = Gem::RequestSet::Lockfile::Tokenizer.new "\n"
    tokenizer.unshift :token
    parser = tokenizer.make_parser nil, nil

    assert_equal :token, parser.get
  end

  def write_lockfile(lockfile)
    File.open @lock_file, "w" do |io|
      io.write lockfile
    end
  end

  def tokenize_lockfile
    Gem::RequestSet::Lockfile::Tokenizer.from_file(@lock_file).to_a
  end
end
