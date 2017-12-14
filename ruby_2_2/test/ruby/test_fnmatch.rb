require 'test/unit'

class TestFnmatch < Test::Unit::TestCase

  def bracket_test(s, t) # `s' should start with neither '!' nor '^'
    0x21.upto(0x7E) do |i|
      assert_equal(t.include?(i.chr), File.fnmatch("[#{s}]", i.chr, File::FNM_DOTMATCH))
      assert_equal(t.include?(i.chr), !File.fnmatch("[^#{s}]", i.chr, File::FNM_DOTMATCH))
      assert_equal(t.include?(i.chr), !File.fnmatch("[!#{s}]", i.chr, File::FNM_DOTMATCH))
    end
  end
  def test_fnmatch
    assert_file.for("[ruby-dev:22819]").fnmatch('\[1\]' , '[1]')
    assert_file.for("[ruby-dev:22815]").fnmatch('*?', 'a')
    assert_file.fnmatch('*/', 'a/')
    assert_file.fnmatch('\[1\]' , '[1]', File::FNM_PATHNAME)
    assert_file.fnmatch('*?', 'a', File::FNM_PATHNAME)
    assert_file.fnmatch('*/', 'a/', File::FNM_PATHNAME)
    # text
    assert_file.fnmatch('cat', 'cat')
    assert_file.not_fnmatch('cat', 'category')
    assert_file.not_fnmatch('cat', 'wildcat')
    # '?' matches any one character
    assert_file.fnmatch('?at', 'cat')
    assert_file.fnmatch('c?t', 'cat')
    assert_file.fnmatch('ca?', 'cat')
    assert_file.fnmatch('?a?', 'cat')
    assert_file.not_fnmatch('c??t', 'cat')
    assert_file.not_fnmatch('??at', 'cat')
    assert_file.not_fnmatch('ca??', 'cat')
    # '*' matches any number (including 0) of any characters
    assert_file.fnmatch('c*', 'cats')
    assert_file.fnmatch('c*ts', 'cats')
    assert_file.fnmatch('*ts', 'cats')
    assert_file.fnmatch('*c*a*t*s*', 'cats')
    assert_file.not_fnmatch('c*t', 'cats')
    assert_file.not_fnmatch('*abc', 'abcabz')
    assert_file.fnmatch('*abz', 'abcabz')
    assert_file.not_fnmatch('a*abc', 'abc')
    assert_file.fnmatch('a*bc', 'abc')
    assert_file.not_fnmatch('a*bc', 'abcd')
    # [seq] : matches any character listed between bracket
    # [!seq] or [^seq] : matches any character except those listed between bracket
    bracket_test("bd-gikl-mosv-x", "bdefgiklmosvwx")
    # escaping character
    assert_file.fnmatch('\?', '?')
    assert_file.not_fnmatch('\?', '\?')
    assert_file.not_fnmatch('\?', 'a')
    assert_file.not_fnmatch('\?', '\a')
    assert_file.fnmatch('\*', '*')
    assert_file.not_fnmatch('\*', '\*')
    assert_file.not_fnmatch('\*', 'cats')
    assert_file.not_fnmatch('\*', '\cats')
    assert_file.fnmatch('\a', 'a')
    assert_file.not_fnmatch('\a', '\a')
    assert_file.fnmatch('[a\-c]', 'a')
    assert_file.fnmatch('[a\-c]', '-')
    assert_file.fnmatch('[a\-c]', 'c')
    assert_file.not_fnmatch('[a\-c]', 'b')
    assert_file.not_fnmatch('[a\-c]', '\\')
    # escaping character loses its meaning if FNM_NOESCAPE is set
    assert_file.not_fnmatch('\?', '?', File::FNM_NOESCAPE)
    assert_file.fnmatch('\?', '\?', File::FNM_NOESCAPE)
    assert_file.not_fnmatch('\?', 'a', File::FNM_NOESCAPE)
    assert_file.fnmatch('\?', '\a', File::FNM_NOESCAPE)
    assert_file.not_fnmatch('\*', '*', File::FNM_NOESCAPE)
    assert_file.fnmatch('\*', '\*', File::FNM_NOESCAPE)
    assert_file.not_fnmatch('\*', 'cats', File::FNM_NOESCAPE)
    assert_file.fnmatch('\*', '\cats', File::FNM_NOESCAPE)
    assert_file.not_fnmatch('\a', 'a', File::FNM_NOESCAPE)
    assert_file.fnmatch('\a', '\a', File::FNM_NOESCAPE)
    assert_file.fnmatch('[a\-c]', 'a', File::FNM_NOESCAPE)
    assert_file.not_fnmatch('[a\-c]', '-', File::FNM_NOESCAPE)
    assert_file.fnmatch('[a\-c]', 'c', File::FNM_NOESCAPE)
    assert_file.fnmatch('[a\-c]', 'b', File::FNM_NOESCAPE) # '\\' < 'b' < 'c'
    assert_file.fnmatch('[a\-c]', '\\', File::FNM_NOESCAPE)
    # case is ignored if FNM_CASEFOLD is set
    assert_file.not_fnmatch('cat', 'CAT')
    assert_file.fnmatch('cat', 'CAT', File::FNM_CASEFOLD)
    assert_file.not_fnmatch('[a-z]', 'D')
    assert_file.fnmatch('[a-z]', 'D', File::FNM_CASEFOLD)
    assert_file.not_fnmatch('[abc]', 'B')
    assert_file.fnmatch('[abc]', 'B', File::FNM_CASEFOLD)
    # wildcard doesn't match '/' if FNM_PATHNAME is set
    assert_file.fnmatch('foo?boo', 'foo/boo')
    assert_file.fnmatch('foo*', 'foo/boo')
    assert_file.not_fnmatch('foo?boo', 'foo/boo', File::FNM_PATHNAME)
    assert_file.not_fnmatch('foo*', 'foo/boo', File::FNM_PATHNAME)
    # wildcard matches leading period if FNM_DOTMATCH is set
    assert_file.not_fnmatch('*', '.profile')
    assert_file.fnmatch('*', '.profile', File::FNM_DOTMATCH)
    assert_file.fnmatch('.*', '.profile')
    assert_file.fnmatch('*', 'dave/.profile')
    assert_file.fnmatch('*/*', 'dave/.profile')
    assert_file.not_fnmatch('*/*', 'dave/.profile', File::FNM_PATHNAME)
    assert_file.fnmatch('*/*', 'dave/.profile', File::FNM_PATHNAME | File::FNM_DOTMATCH)
    # recursive matching
    assert_file.fnmatch('**/foo', 'a/b/c/foo', File::FNM_PATHNAME)
    assert_file.fnmatch('**/foo', '/foo', File::FNM_PATHNAME)
    assert_file.not_fnmatch('**/foo', 'a/.b/c/foo', File::FNM_PATHNAME)
    assert_file.fnmatch('**/foo', 'a/.b/c/foo', File::FNM_PATHNAME | File::FNM_DOTMATCH)
    assert_file.fnmatch('**/foo', '/root/foo', File::FNM_PATHNAME)
    assert_file.fnmatch('**/foo', 'c:/root/foo', File::FNM_PATHNAME)
  end

  def test_extglob
    feature5422 = '[ruby-core:40037]'
    assert_file.for(feature5422).not_fnmatch?( "{.g,t}*", ".gem")
    assert_file.for(feature5422).fnmatch?("{.g,t}*", ".gem", File::FNM_EXTGLOB)
  end

  def test_unmatched_encoding
    bug7911 = '[ruby-dev:47069] [Bug #7911]'
    path = "\u{3042}"
    pattern_ascii = 'a'.encode('US-ASCII')
    pattern_eucjp = path.encode('EUC-JP')
    assert_nothing_raised(ArgumentError, bug7911) do
      assert_file.not_fnmatch(pattern_ascii, path)
      assert_file.not_fnmatch(pattern_eucjp, path)
      assert_file.not_fnmatch(pattern_ascii, path, File::FNM_CASEFOLD)
      assert_file.not_fnmatch(pattern_eucjp, path, File::FNM_CASEFOLD)
      assert_file.fnmatch("{*,#{pattern_ascii}}", path, File::FNM_EXTGLOB)
      assert_file.fnmatch("{*,#{pattern_eucjp}}", path, File::FNM_EXTGLOB)
    end
  end

  def test_unicode
    assert_file.fnmatch("[a-\u3042]*", "\u3042")
    assert_file.not_fnmatch("[a-\u3042]*", "\u3043")
  end
end
