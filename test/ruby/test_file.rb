require 'test/unit'
require 'tempfile'
require 'ut_eof'

class TestFile < Test::Unit::TestCase

  # I don't know Ruby's spec about "unlink-before-close" exactly.
  # This test asserts current behaviour.
  def test_unlink_before_close
    filename = File.basename(__FILE__) + ".#{$$}"
    w = File.open(filename, "w")
    w << "foo"
    w.close
    r = File.open(filename, "r")
    begin
      if /(mswin|bccwin|mingw|emx)/ =~ RUBY_PLATFORM
        assert_raise(Errno::EACCES) {File.unlink(filename)}
      else
	assert_nothing_raised {File.unlink(filename)}
      end
    ensure
      r.close
      File.unlink(filename) if File.exist?(filename)
    end
  end

  include TestEOF
  def open_file(content)
    f = Tempfile.new("test-eof")
    f << content
    f.rewind
    yield f
  end
  alias open_file_rw open_file

  include TestEOF::Seek

  def test_fnmatch
    # from [ruby-dev:22815] and [ruby-dev:22819]
    assert(File.fnmatch('\[1\]' , '[1]'))
    assert(File.fnmatch('*?', 'a'))
    assert(File.fnmatch('*/', 'a/'))
    assert(File.fnmatch('\[1\]' , '[1]', File::FNM_PATHNAME))
    assert(File.fnmatch('*?', 'a', File::FNM_PATHNAME))
    assert(File.fnmatch('*/', 'a/', File::FNM_PATHNAME))
    # text
    assert(File.fnmatch('cat', 'cat'))
    assert(!File.fnmatch('cat', 'category'))
    assert(!File.fnmatch('cat', 'wildcat'))
    # '?' matches any one character
    assert(File.fnmatch('?at', 'cat'))
    assert(File.fnmatch('c?t', 'cat'))
    assert(File.fnmatch('ca?', 'cat'))
    assert(File.fnmatch('?a?', 'cat'))
    assert(!File.fnmatch('c??t', 'cat'))
    assert(!File.fnmatch('??at', 'cat'))
    assert(!File.fnmatch('ca??', 'cat'))
    # '*' matches any number (including 0) of any characters
    assert(File.fnmatch('c*', 'cats'))
    assert(File.fnmatch('c*ts', 'cats'))
    assert(File.fnmatch('*ts', 'cats'))
    assert(File.fnmatch('*c*a*t*s*', 'cats'))
    assert(!File.fnmatch('c*t', 'cats'))
    assert(!File.fnmatch('*abc', 'abcabz'))
    assert(File.fnmatch('*abz', 'abcabz'))
    assert(!File.fnmatch('a*abc', 'abc'))
    assert(File.fnmatch('a*bc', 'abc'))
    assert(!File.fnmatch('a*bc', 'abcd'))
    # matches any character listed between bracket
    assert(File.fnmatch('ca[np]', 'can'))
    assert(File.fnmatch('ca[np]', 'cap'))
    assert(!File.fnmatch('ca[np]', 'cat'))
    assert(File.fnmatch('ca[a-or-z]', 'can'))
    assert(!File.fnmatch('ca[a-or-z]', 'cap'))
    assert(File.fnmatch('ca[a-or-z]', 'cat'))
    # matches any character except those listed between bracket
    assert(File.fnmatch('ca[!pt]', 'can'))
    assert(!File.fnmatch('ca[!pt]', 'cap'))
    assert(!File.fnmatch('ca[!pt]', 'cat'))
    assert(!File.fnmatch('ca[!a-or-z]', 'can'))
    assert(File.fnmatch('ca[!a-or-z]', 'cap'))
    assert(!File.fnmatch('ca[!a-or-z]', 'cat'))
    assert(File.fnmatch('ca[^pt]', 'can'))
    assert(!File.fnmatch('ca[^pt]', 'cap'))
    assert(!File.fnmatch('ca[^pt]', 'cat'))
    assert(!File.fnmatch('ca[^a-or-z]', 'can'))
    assert(File.fnmatch('ca[^a-or-z]', 'cap'))
    assert(!File.fnmatch('ca[^a-or-z]', 'cat'))
    # escaping character
    assert(File.fnmatch('\?', '?'))
    assert(!File.fnmatch('\?', 'a'))
    assert(File.fnmatch('\*', '*'))
    assert(!File.fnmatch('\*', 'cats'))
    assert(File.fnmatch('\a', 'a'))
    assert(File.fnmatch('[a\-c]', 'a'))
    assert(File.fnmatch('[a\-c]', '-'))
    assert(File.fnmatch('[a\-c]', 'c'))
    assert(!File.fnmatch('[a\-c]', 'b'))
    assert(!File.fnmatch('[a\-c]', '\\'))
    # case is ignored if FNM_CASEFOLD is set
    assert(!File.fnmatch('cat', 'CAT'))
    assert(File.fnmatch('cat', 'CAT', File::FNM_CASEFOLD))
    # wildcard doesn't match '/' if FNM_PATHNAME is set
    assert(File.fnmatch('foo?boo', 'foo/boo'))
    assert(File.fnmatch('foo*', 'foo/boo'))
    assert(!File.fnmatch('foo?boo', 'foo/boo', File::FNM_PATHNAME))
    assert(!File.fnmatch('foo*', 'foo/boo', File::FNM_PATHNAME))
    # wildcard matches leading period if FNM_DOTMATCH is set
    assert(!File.fnmatch('*', '.profile'))
    assert(File.fnmatch('*', '.profile', File::FNM_DOTMATCH))
    assert(File.fnmatch('.*', '.profile'))
    assert(File.fnmatch('*', 'dave/.profile'))
    assert(File.fnmatch('*/*', 'dave/.profile'))
    assert(!File.fnmatch('*/*', 'dave/.profile', File::FNM_PATHNAME))
    assert(File.fnmatch('*/*', 'dave/.profile', File::FNM_PATHNAME | File::FNM_DOTMATCH))
    # recursive matching
    assert(File.fnmatch('**/foo', 'a/b/c/foo', File::FNM_PATHNAME))
    assert(File.fnmatch('**/foo', '/foo', File::FNM_PATHNAME))
    assert(!File.fnmatch('**/foo', 'a/.b/c/foo', File::FNM_PATHNAME))
    assert(File.fnmatch('**/foo', 'a/.b/c/foo', File::FNM_PATHNAME | File::FNM_DOTMATCH))
    assert(File.fnmatch('**/foo', '/root/foo', File::FNM_PATHNAME))
    assert(File.fnmatch('**/foo', 'c:/root/foo', File::FNM_PATHNAME))
  end

end
