require 'test/unit'
require 'tmpdir'
require 'rake'

require_relative 'capture_stdout'

class Rake::TestFileList < Test::Unit::TestCase
  FileList = Rake::FileList
  include CaptureStdout

  def setup
    @oldwd = Dir.pwd
    @tmpwd = Dir.mktmpdir
    Dir.chdir(@tmpwd)
    create_test_data
  end

  def teardown
#    FileList.select_default_ignore_patterns
    FileUtils.rm_rf("testdata")
    Dir.chdir(@oldwd)
    FileUtils.rm_rf(@tmpwd)
  end

  def test_delgating_methods_do_not_include_to_a_or_to_ary
    assert ! FileList::DELEGATING_METHODS.include?("to_a"), "should not include to_a"
    assert ! FileList::DELEGATING_METHODS.include?(:to_a), "should not include to_a"
    assert ! FileList::DELEGATING_METHODS.include?("to_ary"), "should not include to_ary"
    assert ! FileList::DELEGATING_METHODS.include?(:to_ary), "should not include to_ary"
  end

  def test_create
    fl = FileList.new
    assert_equal 0, fl.size
  end

  def test_create_with_args
    fl = FileList.new("testdata/*.c", "x")
    assert_equal ["testdata/abc.c", "testdata/x.c", "testdata/xyz.c", "x"].sort,
      fl.sort
  end

  def test_create_with_block
    fl = FileList.new { |f| f.include("x") }
    assert_equal ["x"], fl.resolve
  end

  def test_create_with_brackets
    fl = FileList["testdata/*.c", "x"]
    assert_equal ["testdata/abc.c", "testdata/x.c", "testdata/xyz.c", "x"].sort,
      fl.sort
  end

  def test_create_with_brackets_and_filelist
    fl = FileList[FileList["testdata/*.c", "x"]]
    assert_equal ["testdata/abc.c", "testdata/x.c", "testdata/xyz.c", "x"].sort,
      fl.sort
  end

  def test_include_with_another_array
    fl = FileList.new.include(["x", "y", "z"])
    assert_equal ["x", "y", "z"].sort, fl.sort
  end

  def test_include_with_another_filelist
    fl = FileList.new.include(FileList["testdata/*.c", "x"])
    assert_equal ["testdata/abc.c", "testdata/x.c", "testdata/xyz.c", "x"].sort,
      fl.sort
  end

  def test_append
    fl = FileList.new
    fl << "a.rb" << "b.rb"
    assert_equal ['a.rb', 'b.rb'], fl
  end

  def test_add_many
    fl = FileList.new
    fl.include %w(a d c)
    fl.include('x', 'y')
    assert_equal ['a', 'd', 'c', 'x', 'y'], fl
    assert_equal ['a', 'd', 'c', 'x', 'y'], fl.resolve
  end

  def test_add_return
    f = FileList.new
    g = f << "x"
    assert_equal f.object_id, g.object_id
    h = f.include("y")
    assert_equal f.object_id, h.object_id
  end

  def test_match
    fl = FileList.new
    fl.include(File.expand_path('../test*.rb', __FILE__))
    assert fl.include?(__FILE__)
    assert fl.size > 3
    fl.each { |fn| assert_match(/\.rb$/, fn) }
  end

  def test_add_matching
    fl = FileList.new
    fl << "a.java"
    fl.include(File.dirname(__FILE__)+"/*.rb")
    assert_equal "a.java", fl[0]
    assert fl.size > 2
    assert fl.include?(__FILE__)
  end

  def test_multiple_patterns
    create_test_data
    fl = FileList.new
    fl.include('*.c', '*xist*')
    assert_equal [], fl
    fl.include('testdata/*.c', 'testdata/*xist*')
    assert_equal [
      'testdata/x.c', 'testdata/xyz.c', 'testdata/abc.c', 'testdata/existing'
    ].sort, fl.sort
  end

  def test_square_bracket_pattern
    fl = FileList.new
    fl.include("testdata/abc.[ch]")
    assert fl.size == 2
    assert fl.include?("testdata/abc.c")
    assert fl.include?("testdata/abc.h")
  end

  def test_curly_bracket_pattern
    fl = FileList.new
    fl.include("testdata/abc.{c,h}")
    assert fl.size == 2
    assert fl.include?("testdata/abc.c")
    assert fl.include?("testdata/abc.h")
  end

  def test_reject
    fl = FileList.new
    fl.include %w(testdata/x.c testdata/abc.c testdata/xyz.c testdata/existing)
    fl.reject! { |fn| fn =~ %r{/x} }
    assert_equal [
      'testdata/abc.c', 'testdata/existing'
    ], fl
  end

  def test_exclude
    fl = FileList['testdata/x.c', 'testdata/abc.c', 'testdata/xyz.c', 'testdata/existing']
    fl.each { |fn| touch fn, :verbose => false }
    x = fl.exclude(%r{/x.+\.})
    assert_equal FileList, x.class
    assert_equal %w(testdata/x.c testdata/abc.c testdata/existing), fl
    assert_equal fl.object_id, x.object_id
    fl.exclude('testdata/*.c')
    assert_equal ['testdata/existing'], fl
    fl.exclude('testdata/existing')
    assert_equal [], fl
  end

  def test_excluding_via_block
    fl = FileList['testdata/a.c', 'testdata/b.c', 'testdata/xyz.c']
    fl.exclude { |fn| fn.pathmap('%n') == 'xyz' }
    assert fl.exclude?("xyz.c"), "Should exclude xyz.c"
    assert_equal ['testdata/a.c', 'testdata/b.c'], fl
  end

  def test_exclude_return_on_create
    fl = FileList['testdata/*'].exclude(/.*\.[hcx]$/)
    assert_equal ['testdata/existing', 'testdata/cfiles'].sort, fl.sort
    assert_equal FileList, fl.class
  end

  def test_exclude_with_string_return_on_create
    fl = FileList['testdata/*'].exclude('testdata/abc.c')
    assert_equal %w(testdata/existing testdata/cfiles testdata/x.c testdata/abc.h testdata/abc.x testdata/xyz.c).sort, fl.sort
    assert_equal FileList, fl.class
  end

  def test_default_exclude
    fl = FileList.new
    fl.clear_exclude
    fl.include("**/*~", "**/*.bak", "**/core")
    assert fl.member?("testdata/core"), "Should include core"
    assert fl.member?("testdata/x.bak"), "Should include .bak files"
  end

  def test_unique
    fl = FileList.new
    fl << "x.c" << "a.c" << "b.rb" << "a.c"
    assert_equal ['x.c', 'a.c', 'b.rb', 'a.c'], fl
    fl.uniq!
    assert_equal ['x.c', 'a.c', 'b.rb'], fl
  end

  def test_to_string
    fl = FileList.new
    fl << "a.java" << "b.java"
    assert_equal  "a.java b.java", fl.to_s
    assert_equal  "a.java b.java", "#{fl}"
  end

  def test_to_array
    fl = FileList['a.java', 'b.java']
    assert_equal  ['a.java', 'b.java'], fl.to_a
    assert_equal  Array, fl.to_a.class
    assert_equal  ['a.java', 'b.java'], fl.to_ary
    assert_equal  Array, fl.to_ary.class
  end

  def test_to_s_pending
    fl = FileList['testdata/abc.*']
    result = fl.to_s
    assert_match(%r{testdata/abc\.c}, result)
    assert_match(%r{testdata/abc\.h}, result)
    assert_match(%r{testdata/abc\.x}, result)
    assert_match(%r{(testdata/abc\..\b ?){2}}, result)
  end

  def test_inspect_pending
    fl = FileList['testdata/abc.*']
    result = fl.inspect
    assert_match(%r{"testdata/abc\.c"}, result)
    assert_match(%r{"testdata/abc\.h"}, result)
    assert_match(%r{"testdata/abc\.x"}, result)
    assert_match(%r|^\[("testdata/abc\..", ){2}"testdata/abc\.."\]$|, result)
  end

  def test_sub
    fl = FileList["testdata/*.c"]
    f2 = fl.sub(/\.c$/, ".o")
    assert_equal FileList, f2.class
    assert_equal ["testdata/abc.o", "testdata/x.o", "testdata/xyz.o"].sort,
      f2.sort
    f3 = fl.gsub(/\.c$/, ".o")
    assert_equal FileList, f3.class
    assert_equal ["testdata/abc.o", "testdata/x.o", "testdata/xyz.o"].sort,
      f3.sort
  end

  def test_claim_to_be_a_kind_of_array
    fl = FileList['testdata/*.c']
    assert fl.is_a?(Array)
    assert fl.kind_of?(Array)
  end

  def test_claim_to_be_a_kind_of_filelist
    fl = FileList['testdata/*.c']
    assert fl.is_a?(FileList)
    assert fl.kind_of?(FileList)
  end

  def test_claim_to_be_a_filelist_instance
    fl = FileList['testdata/*.c']
    assert fl.instance_of?(FileList)
  end

  def test_dont_claim_to_be_an_array_instance
    fl = FileList['testdata/*.c']
    assert ! fl.instance_of?(Array)
  end

  def test_sub!
    f = "x/a.c"
    fl = FileList[f, "x/b.c"]
    res = fl.sub!(/\.c$/, ".o")
    assert_equal ["x/a.o", "x/b.o"].sort, fl.sort
    assert_equal "x/a.c", f
    assert_equal fl.object_id, res.object_id
  end

  def test_sub_with_block
    fl = FileList["src/org/onestepback/a.java", "src/org/onestepback/b.java"]
# The block version doesn't work the way I want it to ...
#    f2 = fl.sub(%r{^src/(.*)\.java$}) { |x|  "classes/" + $1 + ".class" }
    f2 = fl.sub(%r{^src/(.*)\.java$}, "classes/\\1.class")
    assert_equal [
      "classes/org/onestepback/a.class",
      "classes/org/onestepback/b.class"
    ].sort,
      f2.sort
  end

  def test_string_ext
    assert_equal "one.net", "one.two".ext("net")
    assert_equal "one.net", "one.two".ext(".net")
    assert_equal "one.net", "one".ext("net")
    assert_equal "one.net", "one".ext(".net")
    assert_equal "one.two.net", "one.two.c".ext(".net")
    assert_equal "one/two.net", "one/two.c".ext(".net")
    assert_equal "one.x/two.net", "one.x/two.c".ext(".net")
    assert_equal "one.x/two.net", "one.x/two".ext(".net")
    assert_equal ".onerc.net", ".onerc.dot".ext("net")
    assert_equal ".onerc.net", ".onerc".ext("net")
    assert_equal ".a/.onerc.net", ".a/.onerc".ext("net")
    assert_equal "one", "one.two".ext('')
    assert_equal "one", "one.two".ext
    assert_equal ".one", ".one.two".ext
    assert_equal ".one", ".one".ext
    assert_equal ".", ".".ext("c")
    assert_equal "..", "..".ext("c")
    # These only need to work in windows
    if Rake::Win32.windows?
      assert_equal "one.x\\two.net", "one.x\\two.c".ext(".net")
      assert_equal "one.x\\two.net", "one.x\\two".ext(".net")
    end
  end

  def test_filelist_ext
    assert_equal FileList['one.c', '.one.c'],
      FileList['one.net', '.one'].ext('c')
  end

  def test_gsub
    create_test_data
    fl = FileList["testdata/*.c"]
    f2 = fl.gsub(/a/, "A")
    assert_equal ["testdAtA/Abc.c", "testdAtA/x.c", "testdAtA/xyz.c"].sort,
      f2.sort
  end

  def test_gsub!
    create_test_data
    f = FileList["testdata/*.c"]
    f.gsub!(/a/, "A")
    assert_equal ["testdAtA/Abc.c", "testdAtA/x.c", "testdAtA/xyz.c"].sort,
      f.sort
  end

  def test_egrep_with_output
    files = FileList[File.expand_path('../test*.rb', __FILE__)]
    the_line_number = __LINE__ + 1
    out = capture_stdout do files.egrep(/PUGH/) end
    assert_match(/:#{the_line_number}:/, out)
  end

  def test_egrep_with_block
    files = FileList[File.expand_path('../test*.rb', __FILE__)]
    found = false
    the_line_number = __LINE__ + 1
    files.egrep(/XYZZY/) do |fn, ln, line |
      assert_equal __FILE__, fn
      assert_equal the_line_number, ln
      assert_match(/files\.egrep/, line)
      found = true
    end
    assert found, "should have found a matching line"
  end

  def test_existing
    fl = FileList['testdata/abc.c', 'testdata/notthere.c']
    assert_equal ["testdata/abc.c"], fl.existing
    assert fl.existing.is_a?(FileList)
  end

  def test_existing!
    fl = FileList['testdata/abc.c', 'testdata/notthere.c']
    result = fl.existing!
    assert_equal ["testdata/abc.c"], fl
    assert_equal fl.object_id, result.object_id
  end

  def test_ignore_special
    f = FileList['testdata/*']
    assert ! f.include?("testdata/CVS"), "Should not contain CVS"
    assert ! f.include?("testdata/.svn"), "Should not contain .svn"
    assert ! f.include?("testdata/.dummy"), "Should not contain dot files"
    assert ! f.include?("testdata/x.bak"), "Should not contain .bak files"
    assert ! f.include?("testdata/x~"), "Should not contain ~ files"
    assert ! f.include?("testdata/core"), "Should not contain core files"
  end

  def test_clear_ignore_patterns
    f = FileList['testdata/*', 'testdata/.svn']
    f.clear_exclude
    assert f.include?("testdata/abc.c")
    assert f.include?("testdata/xyz.c")
    assert f.include?("testdata/CVS")
    assert f.include?("testdata/.svn")
    assert f.include?("testdata/x.bak")
    assert f.include?("testdata/x~")
  end

  def test_exclude_with_alternate_file_seps
    fl = FileList.new
    assert fl.exclude?("x/CVS/y")
    assert fl.exclude?("x\\CVS\\y")
    assert fl.exclude?("x/.svn/y")
    assert fl.exclude?("x\\.svn\\y")
    assert fl.exclude?("x/core")
    assert fl.exclude?("x\\core")
  end

  def test_add_default_exclude_list
    fl = FileList.new
    fl.exclude(/~\d+$/)
    assert fl.exclude?("x/CVS/y")
    assert fl.exclude?("x\\CVS\\y")
    assert fl.exclude?("x/.svn/y")
    assert fl.exclude?("x\\.svn\\y")
    assert fl.exclude?("x/core")
    assert fl.exclude?("x\\core")
    assert fl.exclude?("x/abc~1")
  end

  def test_basic_array_functions
    f = FileList['b', 'c', 'a']
    assert_equal 'b', f.first
    assert_equal 'b', f[0]
    assert_equal 'a', f.last
    assert_equal 'a', f[2]
    assert_equal 'a', f[-1]
    assert_equal ['a', 'b', 'c'], f.sort
    f.sort!
    assert_equal ['a', 'b', 'c'], f
  end

  def test_flatten
    assert_equal ['a', 'testdata/x.c', 'testdata/xyz.c', 'testdata/abc.c'].sort,
      ['a', FileList['testdata/*.c']].flatten.sort
  end

  def test_clone_and_dup
    a = FileList['a', 'b', 'c']
    c = a.clone
    d = a.dup
    a << 'd'
    assert_equal ['a', 'b', 'c', 'd'], a
    assert_equal ['a', 'b', 'c'], c
    assert_equal ['a', 'b', 'c'], d
  end

  def test_dup_and_clone_replicate_taint
    a = FileList['a', 'b', 'c']
    a.taint
    c = a.clone
    d = a.dup
    assert c.tainted?, "Clone should be tainted"
    assert d.tainted?, "Dup should be tainted"
  end

  def test_duped_items_will_thaw
    a = FileList['a', 'b', 'c']
    a.freeze
    d = a.dup
    d << 'more'
    assert_equal ['a', 'b', 'c', 'more'], d
  end

  def test_cloned_items_stay_frozen
    a = FileList['a', 'b', 'c']
    a.freeze
    c = a.clone
    assert_raise(TypeError, RuntimeError) do
      c << 'more'
    end
  end

  def test_array_comparisons
    fl = FileList['b', 'b']
    a = ['b', 'a']
    b = ['b', 'b']
    c = ['b', 'c']
    assert_equal( 1,  fl <=> a )
    assert_equal( 0,  fl <=> b )
    assert_equal( -1, fl <=> c )
    assert_equal( -1, a <=> fl )
    assert_equal( 0,  b <=> fl )
    assert_equal( 1,  c <=> fl )
  end

  def test_array_equality
    a = FileList['a', 'b']
    b = ['a', 'b']
    assert a == b
    assert b == a
#   assert a.eql?(b)
#    assert b.eql?(a)
    assert ! a.equal?(b)
    assert ! b.equal?(a)
  end

  def test_enumeration_methods
    a = FileList['a', 'b']
    b = a.collect { |it| it.upcase }
    assert_equal ['A', 'B'], b
    assert_equal FileList,  b.class

    b = a.map { |it| it.upcase }
    assert_equal ['A', 'B'], b
    assert_equal FileList,  b.class

    b = a.sort
    assert_equal ['a', 'b'], b
    assert_equal FileList,  b.class

    b = a.sort_by { |it| it }
    assert_equal ['a', 'b'], b
    assert_equal FileList,  b.class

    b = a.find_all { |it| it == 'b'}
    assert_equal ['b'], b
    assert_equal FileList,  b.class

    b = a.select { |it| it.size == 1 }
    assert_equal ['a', 'b'], b
    assert_equal FileList,  b.class

    b = a.reject { |it| it == 'b' }
    assert_equal ['a'], b
    assert_equal FileList,  b.class

    b = a.grep(/./)
    assert_equal ['a', 'b'], b
    assert_equal FileList,  b.class

    b = a.partition { |it| it == 'b' }
    assert_equal [['b'], ['a']], b
    assert_equal Array, b.class
    assert_equal FileList,  b[0].class
    assert_equal FileList,  b[1].class

    b = a.zip(['x', 'y']).to_a
    assert_equal [['a', 'x'], ['b', 'y']], b
    assert_equal Array, b.class
    assert_equal Array, b[0].class
    assert_equal Array, b[1].class
  end

  def test_array_operators
    a = ['a', 'b']
    b = ['c', 'd']
    f = FileList['x', 'y']
    g = FileList['w', 'z']

    r = f + g
    assert_equal ['x', 'y', 'w', 'z'], r
    assert_equal FileList, r.class

    r = a + g
    assert_equal ['a', 'b', 'w', 'z'], r
    assert_equal Array, r.class

    r = f + b
    assert_equal ['x', 'y', 'c', 'd'], r
    assert_equal FileList, r.class

    r = FileList['w', 'x', 'y', 'z'] - f
    assert_equal ['w', 'z'], r
    assert_equal FileList, r.class

    r = FileList['w', 'x', 'y', 'z'] & f
    assert_equal ['x', 'y'], r
    assert_equal FileList, r.class

    r = f * 2
    assert_equal ['x', 'y', 'x', 'y'], r
    assert_equal FileList, r.class

    r = f * ','
    assert_equal 'x,y', r
    assert_equal String, r.class

    r = f | ['a', 'x']
    assert_equal ['a', 'x', 'y'].sort, r.sort
    assert_equal FileList, r.class
  end

  def test_other_array_returning_methods
    f = FileList['a', nil, 'b']
    r = f.compact
    assert_equal ['a', 'b'], r
    assert_equal FileList, r.class

    f = FileList['a', 'b']
    r = f.concat(['x', 'y'])
    assert_equal ['a', 'b', 'x', 'y'], r
    assert_equal FileList, r.class

    f = FileList['a', ['b', 'c'], FileList['d', 'e']]
    r = f.flatten
    assert_equal ['a', 'b', 'c', 'd', 'e'], r
    assert_equal FileList, r.class

    f = FileList['a', 'b', 'a']
    r = f.uniq
    assert_equal ['a', 'b'], r
    assert_equal FileList, r.class

    f = FileList['a', 'b', 'c', 'd']
    r = f.values_at(1,3)
    assert_equal ['b', 'd'], r
    assert_equal FileList, r.class
  end

  def test_file_utils_can_use_filelists
    cfiles = FileList['testdata/*.c']

    cp cfiles, @cdir, :verbose => false

    assert File.exist?(File.join(@cdir, 'abc.c'))
    assert File.exist?(File.join(@cdir, 'xyz.c'))
    assert File.exist?(File.join(@cdir, 'x.c'))
  end

  def create_test_data
    verbose(false) do

      mkdir "testdata" unless File.exist? "testdata"
      mkdir "testdata/CVS" rescue nil
      mkdir "testdata/.svn" rescue nil
      @cdir = "testdata/cfiles"
      mkdir @cdir rescue nil
      touch "testdata/.dummy"
      touch "testdata/x.bak"
      touch "testdata/x~"
      touch "testdata/core"
      touch "testdata/x.c"
      touch "testdata/xyz.c"
      touch "testdata/abc.c"
      touch "testdata/abc.h"
      touch "testdata/abc.x"
      touch "testdata/existing"
    end
  end

end
