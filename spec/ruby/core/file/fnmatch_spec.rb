require_relative '../../spec_helper'

describe "File.fnmatch" do
  it "matches entire strings" do
    File.fnmatch('cat', 'cat').should == true
  end

  it "does not match partial strings" do
    File.fnmatch('cat', 'category').should == false
  end

  it "does not support { } patterns by default" do
    File.fnmatch('c{at,ub}s', 'cats').should == false
    File.fnmatch('c{at,ub}s', 'c{at,ub}s').should == true
  end

  it "supports some { } patterns when File::FNM_EXTGLOB is passed" do
    File.fnmatch("{a,b}", "a", File::FNM_EXTGLOB).should == true
    File.fnmatch("{a,b}", "b", File::FNM_EXTGLOB).should == true
    File.fnmatch("c{at,ub}s", "cats", File::FNM_EXTGLOB).should == true
    File.fnmatch("c{at,ub}s", "cubs", File::FNM_EXTGLOB).should == true
    File.fnmatch("-c{at,ub}s-", "-cats-", File::FNM_EXTGLOB).should == true
    File.fnmatch("-c{at,ub}s-", "-cubs-", File::FNM_EXTGLOB).should == true
    File.fnmatch("{a,b,c}{d,e,f}{g,h}", "adg", File::FNM_EXTGLOB).should == true
    File.fnmatch("{a,b,c}{d,e,f}{g,h}", "bdg", File::FNM_EXTGLOB).should == true
    File.fnmatch("{a,b,c}{d,e,f}{g,h}", "ceh", File::FNM_EXTGLOB).should == true
    File.fnmatch("{aa,bb,cc,dd}", "aa", File::FNM_EXTGLOB).should == true
    File.fnmatch("{aa,bb,cc,dd}", "bb", File::FNM_EXTGLOB).should == true
    File.fnmatch("{aa,bb,cc,dd}", "cc", File::FNM_EXTGLOB).should == true
    File.fnmatch("{aa,bb,cc,dd}", "dd", File::FNM_EXTGLOB).should == true
    File.fnmatch("{1,5{a,b{c,d}}}", "1", File::FNM_EXTGLOB).should == true
    File.fnmatch("{1,5{a,b{c,d}}}", "5a", File::FNM_EXTGLOB).should == true
    File.fnmatch("{1,5{a,b{c,d}}}", "5bc", File::FNM_EXTGLOB).should == true
    File.fnmatch("{1,5{a,b{c,d}}}", "5bd", File::FNM_EXTGLOB).should == true
    File.fnmatch("\\\\{a\\,b,b\\}c}", "\\a,b", File::FNM_EXTGLOB).should == true
    File.fnmatch("\\\\{a\\,b,b\\}c}", "\\b}c", File::FNM_EXTGLOB).should == true
  end

  it "doesn't support some { } patterns even when File::FNM_EXTGLOB is passed" do
    File.fnmatch("a{0..3}b", "a0b", File::FNM_EXTGLOB).should == false
    File.fnmatch("a{0..3}b", "a1b", File::FNM_EXTGLOB).should == false
    File.fnmatch("a{0..3}b", "a2b", File::FNM_EXTGLOB).should == false
    File.fnmatch("a{0..3}b", "a3b", File::FNM_EXTGLOB).should == false
    File.fnmatch("{0..12}", "0", File::FNM_EXTGLOB).should == false
    File.fnmatch("{0..12}", "6", File::FNM_EXTGLOB).should == false
    File.fnmatch("{0..12}", "12", File::FNM_EXTGLOB).should == false
    File.fnmatch("{3..-2}", "3", File::FNM_EXTGLOB).should == false
    File.fnmatch("{3..-2}", "0", File::FNM_EXTGLOB).should == false
    File.fnmatch("{3..-2}", "-2", File::FNM_EXTGLOB).should == false
    File.fnmatch("{a..g}", "a", File::FNM_EXTGLOB).should == false
    File.fnmatch("{a..g}", "d", File::FNM_EXTGLOB).should == false
    File.fnmatch("{a..g}", "g", File::FNM_EXTGLOB).should == false
    File.fnmatch("{g..a}", "a", File::FNM_EXTGLOB).should == false
    File.fnmatch("{g..a}", "d", File::FNM_EXTGLOB).should == false
    File.fnmatch("{g..a}", "g", File::FNM_EXTGLOB).should == false
    File.fnmatch("escaping: {{,\\,,\\},\\{}", "escaping: {", File::FNM_EXTGLOB).should == false
    File.fnmatch("escaping: {{,\\,,\\},\\{}", "escaping: ,", File::FNM_EXTGLOB).should == false
    File.fnmatch("escaping: {{,\\,,\\},\\{}", "escaping: }", File::FNM_EXTGLOB).should == false
    File.fnmatch("escaping: {{,\\,,\\},\\{}", "escaping: {", File::FNM_EXTGLOB).should == false
  end

  it "doesn't match an extra } when File::FNM_EXTGLOB is passed" do
    File.fnmatch('c{at,ub}}s', 'cats', File::FNM_EXTGLOB).should == false
  end

  it "matches when both FNM_EXTGLOB and FNM_PATHNAME are passed" do
    File.fnmatch("?.md", "a.md", File::FNM_EXTGLOB | File::FNM_PATHNAME).should == true
  end

  it "matches a single character for each ? character" do
    File.fnmatch('c?t', 'cat').should == true
    File.fnmatch('c??t', 'cat').should == false
  end

  it "matches zero or more characters for each * character" do
    File.fnmatch('c*', 'cats').should == true
    File.fnmatch('c*t', 'c/a/b/t').should == true
  end

  it "does not match unterminated range of characters" do
    File.fnmatch('abc[de', 'abcd').should == false
  end

  it "does not match unterminated range of characters as a literal" do
    File.fnmatch('abc[de', 'abc[de').should == false
  end

  it "matches ranges of characters using bracket expression (e.g. [a-z])" do
    File.fnmatch('ca[a-z]', 'cat').should == true
  end

  it "matches ranges of characters using bracket expression, taking case into account" do
    File.fnmatch('[a-z]', 'D').should == false
    File.fnmatch('[^a-z]', 'D').should == true
    File.fnmatch('[A-Z]', 'd').should == false
    File.fnmatch('[^A-Z]', 'd').should == true
    File.fnmatch('[a-z]', 'D', File::FNM_CASEFOLD).should == true
  end

  it "does not match characters outside of the range of the bracket expression" do
    File.fnmatch('ca[x-z]', 'cat').should == false
    File.fnmatch('/ca[s][s-t]/rul[a-b]/[z]he/[x-Z]orld', '/cats/rule/the/World').should == false
  end

  it "matches ranges of characters using exclusive bracket expression (e.g. [^t] or [!t])" do
    File.fnmatch('ca[^t]', 'cat').should == false
    File.fnmatch('ca[^t]', 'cas').should == true
    File.fnmatch('ca[!t]', 'cat').should == false
  end

  it "matches characters with a case sensitive comparison" do
    File.fnmatch('cat', 'CAT').should == false
  end

  it "matches characters with case insensitive comparison when flags includes FNM_CASEFOLD" do
    File.fnmatch('cat', 'CAT', File::FNM_CASEFOLD).should == true
  end

  platform_is_not :windows do
    it "doesn't match case sensitive characters on platforms with case sensitive paths, when flags include FNM_SYSCASE" do
      File.fnmatch('cat', 'CAT', File::FNM_SYSCASE).should == false
    end
  end

  platform_is :windows do
    it "matches case sensitive characters on platforms with case insensitive paths, when flags include FNM_SYSCASE" do
      File.fnmatch('cat', 'CAT', File::FNM_SYSCASE).should == true
    end
  end

  it "matches wildcard with characters when flags includes FNM_PATHNAME" do
    File.fnmatch('*a', 'aa', File::FNM_PATHNAME).should == true
    File.fnmatch('a*', 'aa', File::FNM_PATHNAME).should == true
    File.fnmatch('a*', 'aaa', File::FNM_PATHNAME).should == true
    File.fnmatch('*a', 'aaa', File::FNM_PATHNAME).should == true
  end

  it "does not match '/' characters with ? or * when flags includes FNM_PATHNAME" do
    File.fnmatch('?', '/', File::FNM_PATHNAME).should == false
    File.fnmatch('*', '/', File::FNM_PATHNAME).should == false
  end

  it "does not match '/' characters inside bracket expressions when flags includes FNM_PATHNAME" do
    File.fnmatch('[/]', '/', File::FNM_PATHNAME).should == false
  end

  it "matches literal ? or * in path when pattern includes \\? or \\*" do
    File.fnmatch('\?', '?').should == true
    File.fnmatch('\?', 'a').should == false

    File.fnmatch('\*', '*').should == true
    File.fnmatch('\*', 'a').should == false
  end

  it "matches literal character (e.g. 'a') in path when pattern includes escaped character (e.g. \\a)" do
    File.fnmatch('\a', 'a').should == true
    File.fnmatch('this\b', 'thisb').should == true
  end

  it "matches '\\' characters in path when flags includes FNM_NOESCAPE" do
    File.fnmatch('\a', '\a', File::FNM_NOESCAPE).should == true
    File.fnmatch('\a', 'a', File::FNM_NOESCAPE).should == false
    File.fnmatch('\[foo\]\[bar\]', '[foo][bar]', File::FNM_NOESCAPE).should == false
  end

  it "escapes special characters inside bracket expression" do
    File.fnmatch('[\?]', '?').should == true
    File.fnmatch('[\*]', '*').should == true
  end

  it "does not match leading periods in filenames with wildcards by default" do
    File.should_not.fnmatch('*', '.profile')
    File.should.fnmatch('*', 'home/.profile')
    File.should.fnmatch('*/*', 'home/.profile')
    File.should_not.fnmatch('*/*', 'dave/.profile', File::FNM_PATHNAME)
  end

  it "matches patterns with leading periods to dotfiles" do
    File.fnmatch('.*', '.profile').should == true
    File.fnmatch('.*', '.profile', File::FNM_PATHNAME).should == true
    File.fnmatch(".*file", "nondotfile").should == false
    File.fnmatch(".*file", "nondotfile", File::FNM_PATHNAME).should == false
  end

  it "does not match directories with leading periods by default with FNM_PATHNAME" do
    File.fnmatch('.*', '.directory/nondotfile', File::FNM_PATHNAME).should == false
    File.fnmatch('.*', '.directory/.profile', File::FNM_PATHNAME).should == false
    File.fnmatch('.*', 'foo/.directory/nondotfile', File::FNM_PATHNAME).should == false
    File.fnmatch('.*', 'foo/.directory/.profile', File::FNM_PATHNAME).should == false
    File.fnmatch('**/.dotfile', '.dotsubdir/.dotfile', File::FNM_PATHNAME).should == false
  end

  it "matches leading periods in filenames when flags includes FNM_DOTMATCH" do
    File.fnmatch('*', '.profile', File::FNM_DOTMATCH).should == true
    File.fnmatch('*', 'home/.profile', File::FNM_DOTMATCH).should == true
  end

  it "matches multiple directories with ** and *" do
    files = '**/*.rb'
    File.fnmatch(files, 'main.rb').should == false
    File.fnmatch(files, './main.rb').should == false
    File.fnmatch(files, 'lib/song.rb').should == true
    File.fnmatch('**.rb', 'main.rb').should == true
    File.fnmatch('**.rb', './main.rb').should == false
    File.fnmatch('**.rb', 'lib/song.rb').should == true
    File.fnmatch('*',     'dave/.profile').should == true
  end

  it "matches multiple directories with ** when flags includes File::FNM_PATHNAME" do
    files = '**/*.rb'
    flags = File::FNM_PATHNAME

    File.fnmatch(files, 'main.rb',               flags).should == true
    File.fnmatch(files, 'one/two/three/main.rb', flags).should == true
    File.fnmatch(files, './main.rb',             flags).should == false

    flags = File::FNM_PATHNAME | File::FNM_DOTMATCH

    File.fnmatch(files, './main.rb',        flags).should == true
    File.fnmatch(files, 'one/two/.main.rb', flags).should == true

    File.fnmatch("**/best/*", 'lib/my/best/song.rb').should == true
  end

  it "returns false if '/' in pattern do not match '/' in path when flags includes FNM_PATHNAME" do
    pattern = '*/*'
    File.fnmatch(pattern, 'dave/.profile', File::FNM_PATHNAME).should == false

    pattern = '**/foo'
    File.fnmatch(pattern, 'a/.b/c/foo', File::FNM_PATHNAME).should == false
  end

  it "returns true if '/' in pattern match '/' in path when flags includes FNM_PATHNAME" do
    pattern = '*/*'
    File.fnmatch(pattern, 'dave/.profile', File::FNM_PATHNAME | File::FNM_DOTMATCH).should == true

    pattern = '**/foo'
    File.fnmatch(pattern, 'a/b/c/foo', File::FNM_PATHNAME).should == true
    File.fnmatch(pattern, '/a/b/c/foo', File::FNM_PATHNAME).should == true
    File.fnmatch(pattern, 'c:/a/b/c/foo', File::FNM_PATHNAME).should == true
    File.fnmatch(pattern, 'a/.b/c/foo', File::FNM_PATHNAME | File::FNM_DOTMATCH).should == true
  end

  it "has special handling for ./ when using * and FNM_PATHNAME" do
    File.fnmatch('./*', '.', File::FNM_PATHNAME).should == false
    File.fnmatch('./*', './', File::FNM_PATHNAME).should == true
    File.fnmatch('./*/', './', File::FNM_PATHNAME).should == false
    File.fnmatch('./**', './', File::FNM_PATHNAME).should == true
    File.fnmatch('./**/', './', File::FNM_PATHNAME).should == true
    File.fnmatch('./*', '.', File::FNM_PATHNAME | File::FNM_DOTMATCH).should == false
    File.fnmatch('./*', './', File::FNM_PATHNAME | File::FNM_DOTMATCH).should == true
    File.fnmatch('./*/', './', File::FNM_PATHNAME | File::FNM_DOTMATCH).should == false
    File.fnmatch('./**', './', File::FNM_PATHNAME | File::FNM_DOTMATCH).should == true
    File.fnmatch('./**/', './', File::FNM_PATHNAME | File::FNM_DOTMATCH).should == true
  end

  it "matches **/* with FNM_PATHNAME to recurse directories" do
    File.fnmatch('nested/**/*', 'nested/subdir', File::FNM_PATHNAME).should == true
    File.fnmatch('nested/**/*', 'nested/subdir/file', File::FNM_PATHNAME).should == true
    File.fnmatch('nested/**/*', 'nested/.dotsubdir', File::FNM_PATHNAME | File::FNM_DOTMATCH).should == true
    File.fnmatch('nested/**/*', 'nested/.dotsubir/.dotfile', File::FNM_PATHNAME | File::FNM_DOTMATCH).should == true
  end

  it "matches ** with FNM_PATHNAME only in current directory" do
    File.fnmatch('nested/**', 'nested/subdir', File::FNM_PATHNAME).should == true
    File.fnmatch('nested/**', 'nested/subdir/file', File::FNM_PATHNAME).should == false
    File.fnmatch('nested/**', 'nested/.dotsubdir', File::FNM_PATHNAME | File::FNM_DOTMATCH).should == true
    File.fnmatch('nested/**', 'nested/.dotsubir/.dotfile', File::FNM_PATHNAME | File::FNM_DOTMATCH).should == false
  end

  it "accepts an object that has a #to_path method" do
    File.fnmatch('\*', mock_to_path('a')).should == false
  end

  it "raises a TypeError if the first and second arguments are not string-like" do
    -> { File.fnmatch(nil, nil, 0, 0) }.should.raise(ArgumentError)
    -> { File.fnmatch(1, 'some/thing') }.should.raise(TypeError)
    -> { File.fnmatch('some/thing', 1) }.should.raise(TypeError)
    -> { File.fnmatch(1, 1) }.should.raise(TypeError)
  end

  it "raises a TypeError if the third argument is not an Integer" do
    -> { File.fnmatch("*/place", "path/to/file", "flags") }.should.raise(TypeError)
    -> { File.fnmatch("*/place", "path/to/file", nil) }.should.raise(TypeError)
  end

  it "does not raise a TypeError if the third argument can be coerced to an Integer" do
    flags = mock("flags")
    flags.should_receive(:to_int).and_return(10)
    -> { File.fnmatch("*/place", "path/to/file", flags) }.should_not.raise
  end

  it "matches multibyte characters" do
    File.fnmatch("*/ä/ø/ñ", "a/ä/ø/ñ").should == true
  end
end

describe "File.fnmatch?" do
  it "is an alias of File.fnmatch" do
    File.method(:fnmatch?).should == File.method(:fnmatch)
  end
end
