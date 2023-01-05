# frozen_string_literal: true
require_relative 'helper'

class TestRDocContextSection < RDoc::TestCase

  def setup
    super

    @top_level = @store.add_file 'file.rb'

    @klass = @top_level.add_class RDoc::NormalClass, 'Object'

    @S = RDoc::Context::Section
    @s = @S.new @klass, 'section', comment('# comment', @top_level, :ruby)
  end

  def test_add_comment
    file1 = @store.add_file 'file1.rb'

    klass = file1.add_class RDoc::NormalClass, 'Klass'

    c1 = RDoc::Comment.new "# :section: section\n", file1
    c2 = RDoc::Comment.new "# hello\n",             file1
    c3 = RDoc::Comment.new "# world\n",             file1

    s = @S.new klass, 'section', c1

    assert_empty s.comments

    s.add_comment nil

    assert_empty s.comments

    s.add_comment c2

    assert_equal [c2], s.comments

    s.add_comment c3

    assert_equal [c2, c3], s.comments
  end

  def test_aref
    assert_equal 'section', @s.aref

    assert_equal '5Buntitled-5D', @S.new(nil, nil, nil).aref

    assert_equal 'one+two', @S.new(nil, 'one two', nil).aref
  end

  def test_eql_eh
    other = @S.new @klass, 'other', comment('# comment', @top_level)

    assert @s.eql? @s
    assert @s.eql? @s.dup
    refute @s.eql? other
  end

  def test_equals
    other = @S.new @klass, 'other', comment('# comment', @top_level)

    assert_equal @s, @s
    assert_equal @s, @s.dup
    refute_equal @s, other
  end

  def test_extract_comment
    assert_equal '',    @s.extract_comment(comment('')).text
    assert_equal '',    @s.extract_comment(comment("# :section: b\n")).text
    assert_equal '# c', @s.extract_comment(comment("# :section: b\n# c")).text
    assert_equal '# c',
                 @s.extract_comment(comment("# a\n# :section: b\n# c")).text
  end

  def test_hash
    other = @S.new @klass, 'other', comment('# comment', @top_level)

    assert_equal @s.hash, @s.hash
    assert_equal @s.hash, @s.dup.hash
    refute_equal @s.hash, other.hash
  end

  def test_marshal_dump
    loaded = Marshal.load Marshal.dump @s

    expected = RDoc::Comment.new('comment', @top_level).parse
    expected = doc(expected)

    assert_equal 'section', loaded.title
    assert_equal expected,  loaded.comments
    assert_nil              loaded.parent, 'parent is set manually'
  end

  def test_marshal_dump_no_comment
    s = @S.new @klass, 'section', comment('')

    loaded = Marshal.load Marshal.dump s

    assert_equal 'section', loaded.title
    assert_empty            loaded.comments
    assert_nil              loaded.parent, 'parent is set manually'
  end

  def test_marshal_load_version_0
    loaded = Marshal.load "\x04\bU:\eRDoc::Context::Section" +
                          "[\bi\x00I\"\fsection\x06:\x06EFo" +
                          ":\eRDoc::Markup::Document\a:\v@parts" +
                          "[\x06o;\a\a;\b[\x06o" +
                          ":\x1CRDoc::Markup::Paragraph\x06;\b" +
                          "[\x06I\"\fcomment\x06;\x06F:\n@fileI" +
                          "\"\ffile.rb\x06;\x06F;\n0"

    expected = doc RDoc::Comment.new('comment', @top_level).parse

    assert_equal 'section', loaded.title
    assert_equal expected,  loaded.comments
    assert_nil              loaded.parent, 'parent is set manually'
  end

  def test_remove_comment_array
    other = @store.add_file 'other.rb'

    other_comment = comment('bogus', other)

    @s.add_comment other_comment

    @s.remove_comment comment('bogus', @top_level)

    assert_equal [other_comment], @s.comments
  end

  def test_remove_comment_document
    other = @store.add_file 'other.rb'

    other_comment = comment('bogus', other)

    @s.add_comment other_comment

    loaded = Marshal.load Marshal.dump @s

    loaded.remove_comment comment('bogus', @top_level)

    assert_equal doc(other_comment.parse), loaded.comments
  end

end
