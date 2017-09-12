# frozen_string_literal: false
require File.expand_path '../xref_test_case', __FILE__

class TestRDocConstant < XrefTestCase

  def setup
    super

    @const = @c1.constants.first
  end

  def test_documented_eh
    top_level = @store.add_file 'file.rb'

    const = RDoc::Constant.new 'CONST', nil, nil
    top_level.add_constant const

    refute const.documented?

    const.comment = comment 'comment'

    assert const.documented?
  end

  def test_documented_eh_alias
    top_level = @store.add_file 'file.rb'

    const = RDoc::Constant.new 'CONST', nil, nil
    top_level.add_constant const

    refute const.documented?

    const.is_alias_for = 'C1'

    refute const.documented?

    @c1.add_comment comment('comment'), @top_level

    assert const.documented?
  end

  def test_full_name
    assert_equal 'C1::CONST', @const.full_name
  end

  def test_is_alias_for
    top_level = @store.add_file 'file.rb'

    c = RDoc::Constant.new 'CONST', nil, 'comment'
    top_level.add_constant c

    assert_nil c.is_alias_for

    c.is_alias_for = 'C1'

    assert_equal @c1, c.is_alias_for

    c.is_alias_for = 'unknown'

    assert_equal 'unknown', c.is_alias_for
  end

  def test_marshal_dump
    top_level = @store.add_file 'file.rb'

    c = RDoc::Constant.new 'CONST', nil, 'this is a comment'
    c.record_location top_level

    aliased = top_level.add_class RDoc::NormalClass, 'Aliased'
    c.is_alias_for = aliased

    cm = top_level.add_class RDoc::NormalClass, 'Klass'
    cm.add_constant c

    section = cm.sections.first

    loaded = Marshal.load Marshal.dump c
    loaded.store = @store

    comment = doc(para('this is a comment'))

    assert_equal c, loaded

    assert_equal aliased,        loaded.is_alias_for
    assert_equal comment,        loaded.comment
    assert_equal top_level,      loaded.file
    assert_equal 'Klass::CONST', loaded.full_name
    assert_equal 'CONST',        loaded.name
    assert_equal :public,        loaded.visibility
    assert_equal cm,             loaded.parent
    assert_equal section,        loaded.section
  end

  def test_marshal_load
    top_level = @store.add_file 'file.rb'

    c = RDoc::Constant.new 'CONST', nil, 'this is a comment'
    c.record_location top_level

    cm = top_level.add_class RDoc::NormalClass, 'Klass'
    cm.add_constant c

    section = cm.sections.first

    loaded = Marshal.load Marshal.dump c
    loaded.store = @store

    comment = doc(para('this is a comment'))

    assert_equal c, loaded

    assert_nil                   loaded.is_alias_for
    assert_equal comment,        loaded.comment
    assert_equal top_level,      loaded.file
    assert_equal 'Klass::CONST', loaded.full_name
    assert_equal 'CONST',        loaded.name
    assert_equal :public,        loaded.visibility
    assert_equal cm,             loaded.parent
    assert_equal section,        loaded.section

    assert loaded.display?
  end

  def test_marshal_load_version_0
    top_level = @store.add_file 'file.rb'

    aliased = top_level.add_class RDoc::NormalClass, 'Aliased'
    cm      = top_level.add_class RDoc::NormalClass, 'Klass'
    section = cm.sections.first

    loaded = Marshal.load "\x04\bU:\x13RDoc::Constant[\x0Fi\x00I" +
                          "\"\nCONST\x06:\x06ETI\"\x11Klass::CONST\x06" +
                          ";\x06T0I\"\fAliased\x06;\x06To" +
                          ":\eRDoc::Markup::Document\a:\v@parts[\x06o" +
                          ":\x1CRDoc::Markup::Paragraph\x06;\b[\x06I" +
                          "\"\x16this is a comment\x06;\x06T:\n@file0I" +
                          "\"\ffile.rb\x06;\x06TI\"\nKlass\x06" +
                          ";\x06Tc\x16RDoc::NormalClass0"

    loaded.store = @store

    comment = doc(para('this is a comment'))

    assert_equal aliased,        loaded.is_alias_for
    assert_equal comment,        loaded.comment
    assert_equal top_level,      loaded.file
    assert_equal 'Klass::CONST', loaded.full_name
    assert_equal 'CONST',        loaded.name
    assert_equal :public,        loaded.visibility
    assert_equal cm,             loaded.parent
    assert_equal section,        loaded.section

    assert loaded.display?
  end

  def test_marshal_round_trip
    top_level = @store.add_file 'file.rb'

    c = RDoc::Constant.new 'CONST', nil, 'this is a comment'
    c.record_location top_level
    c.is_alias_for = 'Unknown'

    cm = top_level.add_class RDoc::NormalClass, 'Klass'
    cm.add_constant c

    section = cm.sections.first

    loaded = Marshal.load Marshal.dump c
    loaded.store = @store

    reloaded = Marshal.load Marshal.dump loaded
    reloaded.store = @store

    assert_equal section,   reloaded.section
    assert_equal 'Unknown', reloaded.is_alias_for
  end

  def test_path
    assert_equal 'C1.html#CONST', @const.path
  end

end
