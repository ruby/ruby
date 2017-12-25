# frozen_string_literal: true
require File.expand_path '../xref_test_case', __FILE__

class TestRDocClassModule < XrefTestCase

  def test_add_comment
    tl1 = @store.add_file 'one.rb'
    tl2 = @store.add_file 'two.rb'
    tl3 = @store.add_file 'three.rb'

    cm = RDoc::ClassModule.new 'Klass'
    cm.add_comment '# comment 1', tl1

    assert_equal [['comment 1', tl1]], cm.comment_location
    assert_equal 'comment 1', cm.comment

    cm.add_comment '# comment 2', tl2

    assert_equal [['comment 1', tl1], ['comment 2', tl2]], cm.comment_location
    assert_equal "comment 1\n---\ncomment 2", cm.comment

    cm.add_comment "# * comment 3", tl3

    assert_equal [['comment 1', tl1],
                  ['comment 2', tl2],
                  ['* comment 3', tl3]], cm.comment_location
    assert_equal "comment 1\n---\ncomment 2\n---\n* comment 3", cm.comment
  end

  def test_add_comment_comment
    cm = RDoc::ClassModule.new 'Klass'

    cm.add_comment comment('comment'), @top_level

    assert_equal 'comment', cm.comment.text
  end

  def test_add_comment_duplicate
    tl1 = @store.add_file 'one.rb'

    cm = RDoc::ClassModule.new 'Klass'
    cm.add_comment '# comment 1', tl1
    cm.add_comment '# comment 2', tl1

    assert_equal [['comment 1', tl1],
                  ['comment 2', tl1]], cm.comment_location
  end

  def test_add_comment_stopdoc
    tl = @store.add_file 'file.rb'

    cm = RDoc::ClassModule.new 'Klass'
    cm.stop_doc

    cm.add_comment '# comment 1', tl

    assert_empty cm.comment
  end

  def test_ancestors
    assert_equal [@parent, "Object"], @child.ancestors
  end

  def test_comment_equals
    cm = RDoc::ClassModule.new 'Klass'
    cm.comment = '# comment 1'

    assert_equal 'comment 1', cm.comment

    cm.comment = '# comment 2'

    assert_equal "comment 1\n---\ncomment 2", cm.comment

    cm.comment = "# * comment 3"

    assert_equal "comment 1\n---\ncomment 2\n---\n* comment 3", cm.comment
  end

  def test_comment_equals_comment
    cm = RDoc::ClassModule.new 'Klass'

    cm.comment = comment 'comment'

    assert_equal 'comment', cm.comment.text
  end

  def test_docuent_self_or_methods
    assert @c1.document_self_or_methods

    @c1.document_self = false

    assert @c1.document_self_or_methods

    @c1_m.document_self = false

    assert @c1.document_self_or_methods

    @c1__m.document_self = false

    refute @c1.document_self_or_methods
  end

  def test_documented_eh
    cm = RDoc::ClassModule.new 'C'

    refute cm.documented?, 'no comments, no markers'

    cm.add_comment '', @top_level

    refute cm.documented?, 'empty comment'

    cm.add_comment 'hi', @top_level

    assert cm.documented?, 'commented'

    cm.comment_location.clear

    refute cm.documented?, 'no comment'

    cm.document_self = nil # notify :nodoc:

    assert cm.documented?, ':nodoc:'
  end

  def test_each_ancestor
    assert_equal [@parent], @child.each_ancestor.to_a
  end

  def test_each_ancestor_cycle
    m_incl = RDoc::Include.new 'M', nil

    m = @top_level.add_module RDoc::NormalModule, 'M'
    m.add_include m_incl

    assert_empty m.each_ancestor.to_a
  end

  # handle making a short module alias of yourself

  def test_find_class_named
    @c2.classes_hash['C2'] = @c2

    assert_nil @c2.find_class_named('C1')
  end

  def test_from_module_comment
    tl = @store.add_file 'file.rb'
    klass = tl.add_class RDoc::NormalModule, 'Klass'
    klass.add_comment 'really a class', tl

    klass = RDoc::ClassModule.from_module RDoc::NormalClass, klass

    assert_equal [['really a class', tl]], klass.comment_location
  end

  def test_marshal_dump
    @store.path = Dir.tmpdir
    tl = @store.add_file 'file.rb'

    ns = tl.add_module RDoc::NormalModule, 'Namespace'

    cm = ns.add_class RDoc::NormalClass, 'Klass', 'Super'
    cm.document_self = true
    cm.record_location tl

    a1 = RDoc::Attr.new nil, 'a1', 'RW', ''
    a1.record_location tl
    a2 = RDoc::Attr.new nil, 'a2', 'RW', '', true
    a2.record_location tl

    m1 = RDoc::AnyMethod.new nil, 'm1'
    m1.record_location tl

    c1 = RDoc::Constant.new 'C1', nil, ''
    c1.record_location tl

    i1 = RDoc::Include.new 'I1', ''
    i1.record_location tl

    e1 = RDoc::Extend.new 'E1', ''
    e1.record_location tl

    section_comment = RDoc::Comment.new('section comment')
    section_comment.location = tl

    assert_equal 1, cm.sections.length, 'sanity, default section only'
    s0 = cm.sections.first
    s1 = cm.add_section 'section', section_comment

    cm.add_attribute a1
    cm.add_attribute a2
    cm.add_method m1
    cm.add_constant c1
    cm.add_include i1
    cm.add_extend e1
    cm.add_comment 'this is a comment', tl

    loaded = Marshal.load Marshal.dump cm
    loaded.store = @store

    assert_equal cm, loaded

    inner = RDoc::Markup::Document.new(
      RDoc::Markup::Paragraph.new('this is a comment'))
    inner.file = tl

    comment = RDoc::Markup::Document.new inner

    assert_equal [a2, a1],           loaded.attributes.sort
    assert_equal comment,            loaded.comment
    assert_equal [c1],               loaded.constants
    assert_equal 'Namespace::Klass', loaded.full_name
    assert_equal [i1],               loaded.includes
    assert_equal [e1],               loaded.extends
    assert_equal [m1],               loaded.method_list
    assert_equal 'Klass',            loaded.name
    assert_equal 'Super',            loaded.superclass
    assert_equal [tl],               loaded.in_files
    assert_equal 'Namespace',        loaded.parent.name

    expected = { nil => s0, 'section' => s1 }
    assert_equal expected, loaded.sections_hash

    assert_equal tl, loaded.attributes.first.file

    assert_equal tl, loaded.constants.first.file

    assert_equal tl, loaded.includes.first.file

    assert_equal tl, loaded.extends.first.file

    assert_equal tl, loaded.method_list.first.file
  end

  def test_marshal_dump_visibilty
    @store.path = Dir.tmpdir
    tl = @store.add_file 'file.rb'

    ns = tl.add_module RDoc::NormalModule, 'Namespace'

    cm = ns.add_class RDoc::NormalClass, 'Klass', 'Super'
    cm.record_location tl

    a1 = RDoc::Attr.new nil, 'a1', 'RW', ''
    a1.record_location tl
    a1.document_self = false

    m1 = RDoc::AnyMethod.new nil, 'm1'
    m1.record_location tl
    m1.document_self = false

    c1 = RDoc::Constant.new 'C1', nil, ''
    c1.record_location tl
    c1.document_self = false

    i1 = RDoc::Include.new 'I1', ''
    i1.record_location tl
    i1.document_self = false

    e1 = RDoc::Extend.new 'E1', ''
    e1.record_location tl
    e1.document_self = false

    section_comment = RDoc::Comment.new('section comment')
    section_comment.location = tl

    assert_equal 1, cm.sections.length, 'sanity, default section only'

    cm.add_attribute a1
    cm.add_method m1
    cm.add_constant c1
    cm.add_include i1
    cm.add_extend e1
    cm.add_comment 'this is a comment', tl

    loaded = Marshal.load Marshal.dump cm
    loaded.store = @store

    assert_equal cm, loaded

    assert_empty loaded.attributes
    assert_empty loaded.constants
    assert_empty loaded.includes
    assert_empty loaded.extends
    assert_empty loaded.method_list
  end

  def test_marshal_load_version_0
    tl = @store.add_file 'file.rb'
    ns = tl.add_module RDoc::NormalModule, 'Namespace'
    cm = ns.add_class RDoc::NormalClass, 'Klass', 'Super'

    a = RDoc::Attr.new(nil, 'a1', 'RW', '')
    m = RDoc::AnyMethod.new(nil, 'm1')
    c = RDoc::Constant.new('C1', nil, '')
    i = RDoc::Include.new('I1', '')

    s0 = cm.sections.first

    cm.add_attribute a
    cm.add_method m
    cm.add_constant c
    cm.add_include i
    cm.add_comment 'this is a comment', tl

    loaded = Marshal.load "\x04\bU:\x16RDoc::NormalClass[\x0Ei\x00\"\nKlass" +
                          "\"\x15Namespace::KlassI\"\nSuper\x06:\x06EF" +
                          "o:\eRDoc::Markup::Document\x06:\v@parts[\x06" +
                          "o:\x1CRDoc::Markup::Paragraph\x06;\b[\x06I" +
                          "\"\x16this is a comment\x06;\x06F[\x06[\aI" +
                          "\"\aa1\x06;\x06FI\"\aRW\x06;\x06F[\x06[\aI" +
                          "\"\aC1\x06;\x06Fo;\a\x06;\b[\x00[\x06[\aI" +
                          "\"\aI1\x06;\x06Fo;\a\x06;\b[\x00[\a[\aI" +
                          "\"\nclass\x06;\x06F[\b[\a:\vpublic[\x00[\a" +
                          ":\x0Eprotected[\x00[\a:\fprivate[\x00[\aI" +
                          "\"\rinstance\x06;\x06F[\b[\a;\n[\x06I" +
                          "\"\am1\x06;\x06F[\a;\v[\x00[\a;\f[\x00"

    loaded.store = @store

    assert_equal cm, loaded

    comment = RDoc::Markup::Document.new(
                RDoc::Markup::Paragraph.new('this is a comment'))

    assert_equal [a],                loaded.attributes
    assert_equal comment,            loaded.comment
    assert_equal [c],                loaded.constants
    assert_equal 'Namespace::Klass', loaded.full_name
    assert_equal [i],                loaded.includes
    assert_equal [m],                loaded.method_list
    assert_equal 'Klass',            loaded.name
    assert_equal 'Super',            loaded.superclass
    assert_nil                       loaded.file
    assert_empty                     loaded.in_files
    assert_nil                       loaded.parent
    assert                           loaded.current_section

    expected = { nil => s0 }
    assert_equal expected, loaded.sections_hash

    assert loaded.display?
  end

  def test_marshal_load_version_1
    tl = @store.add_file 'file.rb'

    ns = tl.add_module RDoc::NormalModule, 'Namespace'

    cm = ns.add_class RDoc::NormalClass, 'Klass', 'Super'
    cm.record_location tl

    a1 = RDoc::Attr.new nil, 'a1', 'RW', ''
    a1.record_location tl
    a2 = RDoc::Attr.new nil, 'a2', 'RW', '', true
    a2.record_location tl

    m1 = RDoc::AnyMethod.new nil, 'm1'
    m1.record_location tl

    c1 = RDoc::Constant.new 'C1', nil, ''
    c1.record_location tl

    i1 = RDoc::Include.new 'I1', ''
    i1.record_location tl

    s0 = cm.sections.first

    cm.add_attribute a1
    cm.add_attribute a2
    cm.add_method m1
    cm.add_constant c1
    cm.add_include i1
    cm.add_comment 'this is a comment', tl

    loaded = Marshal.load "\x04\bU:\x16RDoc::NormalClass[\x0Ei\x06I\"\nKlass" +
                          "\x06:\x06EFI\"\x15Namespace::Klass\x06;\x06FI" +
                          "\"\nSuper\x06;\x06Fo:\eRDoc::Markup::Document\a" +
                          ":\v@parts[\x06o;\a\a;\b[\x06o" +
                          ":\x1CRDoc::Markup::Paragraph\x06;\b" +
                          "[\x06I\"\x16this is a comment\x06;\x06F" +
                          ":\n@fileI\"\ffile.rb\x06;\x06F;\n0[\a[\nI" +
                          "\"\aa2\x06;\x06FI\"\aRW\x06;\x06F:\vpublicT@\x11" +
                          "[\nI\"\aa1\x06;\x06FI\"\aRW\x06;\x06F;\vF@\x11" +
                          "[\x06[\bI\"\aC1\x06;\x06Fo;\a\a;\b[\x00;\n0@\x11" +
                          "[\x06[\bI\"\aI1\x06;\x06Fo;\a\a;\b[\x00;\n0@\x11" +
                          "[\a[\aI\"\nclass\x06;\x06F[\b[\a;\v[\x00" +
                          "[\a:\x0Eprotected[\x00[\a:\fprivate[\x00[\aI" +
                          "\"\rinstance\x06;\x06F[\b[\a;\v[\x06[\aI" +
                          "\"\am1\x06;\x06F@\x11[\a;\f[\x00[\a;\r[\x00"

    loaded.store = @store

    assert_equal cm, loaded

    inner = RDoc::Markup::Document.new(
      RDoc::Markup::Paragraph.new('this is a comment'))
    inner.file = tl

    comment = RDoc::Markup::Document.new inner

    assert_equal [a2, a1],           loaded.attributes.sort
    assert_equal comment,            loaded.comment
    assert_equal [c1],               loaded.constants
    assert_equal 'Namespace::Klass', loaded.full_name
    assert_equal [i1],               loaded.includes
    assert_empty                     loaded.extends
    assert_equal [m1],               loaded.method_list
    assert_equal 'Klass',            loaded.name
    assert_equal 'Super',            loaded.superclass
    assert_empty                     loaded.in_files
    assert_nil                       loaded.parent
    assert                           loaded.current_section

    assert_equal tl, loaded.attributes.first.file
    assert_equal tl, loaded.constants.first.file
    assert_equal tl, loaded.includes.first.file
    assert_equal tl, loaded.method_list.first.file

    expected = { nil => s0 }
    assert_equal expected, loaded.sections_hash
  end

  def test_marshal_load_version_2
    tl = @store.add_file 'file.rb'

    ns = tl.add_module RDoc::NormalModule, 'Namespace'

    cm = ns.add_class RDoc::NormalClass, 'Klass', 'Super'
    cm.record_location tl

    a1 = RDoc::Attr.new nil, 'a1', 'RW', ''
    a1.record_location tl
    a2 = RDoc::Attr.new nil, 'a2', 'RW', '', true
    a2.record_location tl

    m1 = RDoc::AnyMethod.new nil, 'm1'
    m1.record_location tl

    c1 = RDoc::Constant.new 'C1', nil, ''
    c1.record_location tl

    i1 = RDoc::Include.new 'I1', ''
    i1.record_location tl

    e1 = RDoc::Extend.new 'E1', ''
    e1.record_location tl

    s0 = cm.sections.first

    cm.add_attribute a1
    cm.add_attribute a2
    cm.add_method m1
    cm.add_constant c1
    cm.add_include i1
    cm.add_extend e1
    cm.add_comment 'this is a comment', tl

    loaded = Marshal.load "\x04\bU:\x16RDoc::NormalClass[\x0Fi\aI\"\nKlass" +
                          "\x06:\x06EFI\"\x15Namespace::Klass\x06;\x06FI" +
                          "\"\nSuper\x06;\x06Fo:\eRDoc::Markup::Document\a" +
                          ":\v@parts[\x06o;\a\a;\b[\x06o" +
                          ":\x1CRDoc::Markup::Paragraph\x06;\b" +
                          "[\x06I\"\x16this is a comment\x06;\x06F" +
                          ":\n@fileI\"\ffile.rb\x06;\x06F;\n0[\a[\nI" +
                          "\"\aa2\x06;\x06FI\"\aRW\x06;\x06F:\vpublicT@\x11" +
                          "[\nI\"\aa1\x06;\x06FI\"\aRW\x06;\x06F;\vF@\x11" +
                          "[\x06[\bI\"\aC1\x06;\x06Fo;\a\a;\b[\x00;\n0@\x11" +
                          "[\x06[\bI\"\aI1\x06;\x06Fo;\a\a;\b[\x00;\n0@\x11" +
                          "[\a[\aI\"\nclass\x06;\x06F[\b[\a;\v[\x00" +
                          "[\a:\x0Eprotected[\x00[\a:\fprivate[\x00[\aI" +
                          "\"\rinstance\x06;\x06F[\b[\a;\v[\x06[\aI" +
                          "\"\am1\x06;\x06F@\x11[\a;\f[\x00[\a;\r[\x00" +
                          "[\x06[\bI\"\aE1\x06;\x06Fo;\a\a;\b[\x00;\n0@\x11"

    loaded.store = @store

    assert_equal cm, loaded

    inner = RDoc::Markup::Document.new(
      RDoc::Markup::Paragraph.new('this is a comment'))
    inner.file = tl

    comment = RDoc::Markup::Document.new inner

    assert_equal [a2, a1],           loaded.attributes.sort
    assert_equal comment,            loaded.comment
    assert_equal [c1],               loaded.constants
    assert_equal 'Namespace::Klass', loaded.full_name
    assert_equal [i1],               loaded.includes
    assert_equal [e1],               loaded.extends
    assert_equal [m1],               loaded.method_list
    assert_equal 'Klass',            loaded.name
    assert_equal 'Super',            loaded.superclass
    assert_empty                     loaded.in_files
    assert_nil                       loaded.parent
    assert                           loaded.current_section

    assert_equal tl, loaded.attributes. first.file
    assert_equal tl, loaded.constants.  first.file
    assert_equal tl, loaded.includes.   first.file
    assert_equal tl, loaded.extends.    first.file
    assert_equal tl, loaded.method_list.first.file

    expected = { nil => s0 }
    assert_equal expected, loaded.sections_hash
  end

  def test_marshal_load_version_3
    tl = @store.add_file 'file.rb'

    ns = tl.add_module RDoc::NormalModule, 'Namespace'

    cm = ns.add_class RDoc::NormalClass, 'Klass', 'Super'
    cm.record_location tl

    a1 = RDoc::Attr.new nil, 'a1', 'RW', ''
    a1.record_location tl
    a2 = RDoc::Attr.new nil, 'a2', 'RW', '', true
    a2.record_location tl

    m1 = RDoc::AnyMethod.new nil, 'm1'
    m1.record_location tl

    c1 = RDoc::Constant.new 'C1', nil, ''
    c1.record_location tl

    i1 = RDoc::Include.new 'I1', ''
    i1.record_location tl

    e1 = RDoc::Extend.new 'E1', ''
    e1.record_location tl

    section_comment = RDoc::Comment.new('section comment')
    section_comment.location = tl

    assert_equal 1, cm.sections.length, 'sanity, default section only'
    s0 = cm.sections.first
    s1 = cm.add_section 'section', section_comment

    cm.add_attribute a1
    cm.add_attribute a2
    cm.add_method m1
    cm.add_constant c1
    cm.add_include i1
    cm.add_extend e1
    cm.add_comment 'this is a comment', tl

    loaded = Marshal.load "\x04\bU:\x16RDoc::NormalClass[\x13i\bI\"\nKlass" +
                          "\x06:\x06ETI\"\x15Namespace::Klass\x06;\x06TI" +
                          "\"\nSuper\x06;\x06To:\eRDoc::Markup::Document\a" +
                          ":\v@parts[\x06o;\a\a;\b[\x06o" +
                          ":\x1CRDoc::Markup::Paragraph\x06;\b[\x06I" +
                          "\"\x16this is a comment\x06;\x06T:\n@fileI" +
                          "\"\ffile.rb\x06;\x06T;\n0[\a[\nI\"\aa2\x06;" +
                          "\x06TI\"\aRW\x06;\x06T:\vpublicT@\x11[\nI" +
                          "\"\aa1\x06;\x06TI\"\aRW\x06;\x06T;\vF@\x11" +
                          "[\x06U:\x13RDoc::Constant[\x0Fi\x00I\"\aC1\x06" +
                          ";\x06TI\"\x19Namespace::Klass::C1\x06;\x06T00o" +
                          ";\a\a;\b[\x00;\n0@\x11@\ac\x16RDoc::NormalClass0" +
                          "[\x06[\bI\"\aI1\x06;\x06To;\a\a;\b[\x00;\n0@\x11" +
                          "[\a[\aI\"\nclass\x06;\x06T[\b[\a;\v[\x00[\a" +
                          ":\x0Eprotected[\x00[\a:\fprivate[\x00[\aI" +
                          "\"\rinstance\x06;\x06T[\b[\a;\v[\x06[\aI" +
                          "\"\am1\x06;\x06T@\x11[\a;\r[\x00[\a;\x0E[\x00" +
                          "[\x06[\bI\"\aE1\x06;\x06To;\a\a;\b[\x00;\n0@\x11" +
                          "[\aU:\eRDoc::Context::Section[\bi\x000o;\a\a;\b" +
                          "[\x00;\n0U;\x0F[\bi\x00I\"\fsection\x06;\x06To" +
                          ";\a\a;\b[\x06o;\a\a;\b[\x06o;\t\x06;\b[\x06I" +
                          "\"\x14section comment\x06;\x06T;\n@\x11;\n0" +
                          "[\x06@\x11I\"\x0ENamespace\x06" +
                          ";\x06Tc\x17RDoc::NormalModule"

    loaded.store = @store

    assert_equal cm, loaded

    inner = RDoc::Markup::Document.new(
      RDoc::Markup::Paragraph.new('this is a comment'))
    inner.file = tl

    comment = RDoc::Markup::Document.new inner

    assert_equal [a2, a1],           loaded.attributes.sort
    assert_equal comment,            loaded.comment
    assert_equal [c1],               loaded.constants
    assert_equal 'Namespace::Klass', loaded.full_name
    assert_equal [i1],               loaded.includes
    assert_equal [e1],               loaded.extends
    assert_equal [m1],               loaded.method_list
    assert_equal 'Klass',            loaded.name
    assert_equal 'Super',            loaded.superclass
    assert_equal 'Namespace',        loaded.parent.name
    assert                           loaded.current_section

    expected = {
      nil       => s0,
      'section' => s1,
    }

    assert_equal expected,           loaded.sections_hash
    assert_equal [tl],               loaded.in_files

    assert_equal tl, loaded.attributes. first.file
    assert_equal tl, loaded.constants.  first.file
    assert_equal tl, loaded.includes.   first.file
    assert_equal tl, loaded.extends.    first.file
    assert_equal tl, loaded.method_list.first.file
  end

  def test_merge
    tl = @store.add_file 'one.rb'
    p1  = tl.add_class RDoc::NormalClass, 'Parent'
    c1  = p1.add_class RDoc::NormalClass, 'Klass'

    c2 = RDoc::NormalClass.new 'Klass'

    c2.merge c1

    assert_equal 'Parent', c1.parent_name, 'original parent name'
    assert_equal 'Parent', c2.parent_name, 'merged parent name'

    assert c1.current_section, 'original current_section'
    assert c2.current_section, 'merged current_section'
  end

  def test_merge_attributes
    tl1 = @store.add_file 'one.rb'
    tl2 = @store.add_file 'two.rb'

    cm1 = RDoc::ClassModule.new 'Klass'

    attr = cm1.add_attribute RDoc::Attr.new(nil, 'a1', 'RW', '')
    attr.record_location tl1
    attr = cm1.add_attribute RDoc::Attr.new(nil, 'a3', 'R', '')
    attr.record_location tl1
    attr = cm1.add_attribute RDoc::Attr.new(nil, 'a4', 'R', '')
    attr.record_location tl1

    cm2 = RDoc::ClassModule.new 'Klass'
    # TODO allow merging when comment == ''
    cm2.instance_variable_set :@comment, @RM::Document.new

    attr = cm2.add_attribute RDoc::Attr.new(nil, 'a2', 'RW', '')
    attr.record_location tl2
    attr = cm2.add_attribute RDoc::Attr.new(nil, 'a3', 'W', '')
    attr.record_location tl1
    attr = cm2.add_attribute RDoc::Attr.new(nil, 'a4', 'W', '')
    attr.record_location tl1

    cm1.merge cm2

    expected = [
      RDoc::Attr.new(nil, 'a2', 'RW', ''),
      RDoc::Attr.new(nil, 'a3', 'W',  ''),
      RDoc::Attr.new(nil, 'a4', 'W',  ''),
    ]

    expected.each do |a| a.parent = cm1 end
    assert_equal expected, cm1.attributes.sort
  end

  def test_merge_attributes_version_0
    tl1 = @store.add_file 'one.rb'

    cm1 = RDoc::ClassModule.new 'Klass'

    attr = cm1.add_attribute RDoc::Attr.new(nil, 'a1', 'RW', '')
    attr.record_location tl1
    attr = cm1.add_attribute RDoc::Attr.new(nil, 'a3', 'R', '')
    attr.record_location tl1
    attr = cm1.add_attribute RDoc::Attr.new(nil, 'a4', 'R', '')
    attr.record_location tl1

    cm2 = RDoc::ClassModule.new 'Klass'
    # TODO allow merging when comment == ''
    cm2.instance_variable_set :@comment, @RM::Document.new

    attr = cm2.add_attribute RDoc::Attr.new(nil, 'a2', 'RW', '')
    attr = cm2.add_attribute RDoc::Attr.new(nil, 'a3', 'W', '')
    attr = cm2.add_attribute RDoc::Attr.new(nil, 'a4', 'W', '')

    cm1.merge cm2

    expected = [
      RDoc::Attr.new(nil, 'a1', 'RW', ''),
      RDoc::Attr.new(nil, 'a2', 'RW', ''),
      RDoc::Attr.new(nil, 'a3', 'RW', ''),
      RDoc::Attr.new(nil, 'a4', 'RW', ''),
    ]

    expected.each do |a| a.parent = cm1 end
    assert_equal expected, cm1.attributes.sort
  end

  def test_merge_collections_drop
    tl = @store.add_file 'file'

    cm1 = RDoc::ClassModule.new 'C'
    cm1.record_location tl

    const = cm1.add_constant RDoc::Constant.new('CONST', nil, nil)
    const.record_location tl

    cm2 = RDoc::ClassModule.new 'C'
    cm2.record_location tl

    added = []
    removed = []

    cm1.merge_collections cm1.constants, cm2.constants, cm2.in_files do |add, c|
      if add then
        added << c
      else
        removed << c
      end
    end

    assert_empty added
    assert_equal [const], removed
  end

  def test_merge_comment
    tl1 = @store.add_file 'one.rb'
    tl2 = @store.add_file 'two.rb'

    cm1 = tl1.add_class RDoc::ClassModule, 'Klass'
    cm1.add_comment 'klass 1', tl1
    cm1.record_location tl1

    cm2 = tl1.add_class RDoc::NormalClass, 'Klass'
    cm2.add_comment 'klass 2', tl2
    cm2.add_comment 'klass 3', tl1
    cm2.record_location tl1
    cm2.record_location tl2

    cm2 = Marshal.load Marshal.dump cm2
    cm2.store = @store

    cm1.merge cm2

    inner1 = @RM::Document.new @RM::Paragraph.new 'klass 3'
    inner1.file = 'one.rb'
    inner2 = @RM::Document.new @RM::Paragraph.new 'klass 2'
    inner2.file = 'two.rb'

    expected = @RM::Document.new inner2, inner1

    assert_equal expected, cm1.comment
  end

  def test_merge_comment_version_0
    tl = @store.add_file 'file.rb'

    cm1 = RDoc::ClassModule.new 'Klass'
    cm1.add_comment 'klass 1', tl

    cm2 = RDoc::ClassModule.new 'Klass'

    cm2.instance_variable_set(:@comment,
                              @RM::Document.new(
                                @RM::Paragraph.new('klass 2')))
    cm2.instance_variable_set :@comment_location, @RM::Document.new(cm2.comment)

    cm1.merge cm2

    inner = @RM::Document.new @RM::Paragraph.new 'klass 1'
    inner.file = 'file.rb'

    expected = @RM::Document.new \
      inner,
      @RM::Document.new(@RM::Paragraph.new('klass 2'))

    assert_equal expected, cm1.comment
  end

  def test_merge_constants
    tl1 = @store.add_file 'one.rb'
    tl2 = @store.add_file 'two.rb'

    cm1 = tl1.add_class RDoc::ClassModule, 'Klass'

    const = cm1.add_constant RDoc::Constant.new('C1', nil, 'one')
    const.record_location tl1
    const = cm1.add_constant RDoc::Constant.new('C3', nil, 'one')
    const.record_location tl1

    store = RDoc::Store.new
    tl = store.add_file 'one.rb'
    cm2 = tl.add_class RDoc::ClassModule, 'Klass'
    cm2.instance_variable_set :@comment, @RM::Document.new

    const = cm2.add_constant RDoc::Constant.new('C2', nil, 'two')
    const.record_location tl2
    const = cm2.add_constant RDoc::Constant.new('C3', nil, 'one')
    const.record_location tl1
    const = cm2.add_constant RDoc::Constant.new('C4', nil, 'one')
    const.record_location tl1

    cm1.merge cm2

    expected = [
      RDoc::Constant.new('C2', nil, 'two'),
      RDoc::Constant.new('C3', nil, 'one'),
      RDoc::Constant.new('C4', nil, 'one'),
    ]

    expected.each do |a| a.parent = cm1 end

    assert_equal expected, cm1.constants.sort
  end

  def test_merge_constants_version_0
    tl1 = @store.add_file 'one.rb'

    cm1 = tl1.add_class RDoc::ClassModule, 'Klass'

    const = cm1.add_constant RDoc::Constant.new('C1', nil, 'one')
    const.record_location tl1
    const = cm1.add_constant RDoc::Constant.new('C3', nil, 'one')
    const.record_location tl1

    store = RDoc::Store.new
    tl = store.add_file 'one.rb'
    cm2 = tl.add_class RDoc::ClassModule, 'Klass'
    cm2.instance_variable_set :@comment, @RM::Document.new

    const = cm2.add_constant RDoc::Constant.new('C2', nil, 'two')
    const = cm2.add_constant RDoc::Constant.new('C3', nil, 'two')
    const = cm2.add_constant RDoc::Constant.new('C4', nil, 'two')

    cm1.merge cm2

    expected = [
      RDoc::Constant.new('C1', nil, 'one'),
      RDoc::Constant.new('C2', nil, 'two'),
      RDoc::Constant.new('C3', nil, 'one'),
      RDoc::Constant.new('C4', nil, 'two'),
    ]

    expected.each do |a| a.parent = cm1 end

    assert_equal expected, cm1.constants.sort
  end

  def test_merge_extends
    tl1 = @store.add_file 'one.rb'
    cm1 = tl1.add_class RDoc::ClassModule, 'Klass'

    ext = cm1.add_extend RDoc::Extend.new('I1', 'one')
    ext.record_location tl1
    ext = cm1.add_extend RDoc::Extend.new('I3', 'one')
    ext.record_location tl1

    tl2 = @store.add_file 'two.rb'
    tl2.store = RDoc::Store.new

    cm2 = tl2.add_class RDoc::ClassModule, 'Klass'
    cm2.instance_variable_set :@comment, @RM::Document.new

    ext = cm2.add_extend RDoc::Extend.new('I2', 'two')
    ext.record_location tl2
    ext = cm2.add_extend RDoc::Extend.new('I3', 'one')
    ext.record_location tl1
    ext = cm2.add_extend RDoc::Extend.new('I4', 'one')
    ext.record_location tl1

    cm1.merge cm2

    expected = [
      RDoc::Extend.new('I2', 'two'),
      RDoc::Extend.new('I3', 'one'),
      RDoc::Extend.new('I4', 'one'),
    ]

    expected.each do |a| a.parent = cm1 end

    assert_equal expected, cm1.extends.sort
  end

  def test_merge_includes
    tl1 = @store.add_file 'one.rb'

    cm1 = tl1.add_class RDoc::ClassModule, 'Klass'

    incl = cm1.add_include RDoc::Include.new('I1', 'one')
    incl.record_location tl1
    incl = cm1.add_include RDoc::Include.new('I3', 'one')
    incl.record_location tl1

    tl2 = @store.add_file 'two.rb'
    tl2.store = RDoc::Store.new

    cm2 = tl2.add_class RDoc::ClassModule, 'Klass'
    cm2.instance_variable_set :@comment, @RM::Document.new

    incl = cm2.add_include RDoc::Include.new('I2', 'two')
    incl.record_location tl2
    incl = cm2.add_include RDoc::Include.new('I3', 'one')
    incl.record_location tl1
    incl = cm2.add_include RDoc::Include.new('I4', 'one')
    incl.record_location tl1

    cm1.merge cm2

    expected = [
      RDoc::Include.new('I2', 'two'),
      RDoc::Include.new('I3', 'one'),
      RDoc::Include.new('I4', 'one'),
    ]

    expected.each do |a| a.parent = cm1 end

    assert_equal expected, cm1.includes.sort
  end

  def test_merge_includes_version_0
    tl1 = @store.add_file 'one.rb'

    cm1 = tl1.add_class RDoc::ClassModule, 'Klass'

    incl = cm1.add_include RDoc::Include.new('I1', 'one')
    incl.record_location tl1
    incl = cm1.add_include RDoc::Include.new('I3', 'one')
    incl.record_location tl1

    tl2 = @store.add_file 'one.rb'
    tl2.store = RDoc::Store.new

    cm2 = tl2.add_class RDoc::ClassModule, 'Klass'
    cm2.instance_variable_set :@comment, @RM::Document.new

    incl = cm2.add_include RDoc::Include.new('I2', 'two')
    incl = cm2.add_include RDoc::Include.new('I3', 'two')
    incl = cm2.add_include RDoc::Include.new('I4', 'two')

    cm1.merge cm2

    expected = [
      RDoc::Include.new('I1', 'one'),
      RDoc::Include.new('I2', 'two'),
      RDoc::Include.new('I3', 'one'),
      RDoc::Include.new('I4', 'two'),
    ]

    expected.each do |a| a.parent = cm1 end

    assert_equal expected, cm1.includes.sort
  end

  def test_merge_methods
    tl1 = @store.add_file 'one.rb'
    tl2 = @store.add_file 'two.rb'

    cm1 = tl1.add_class RDoc::NormalClass, 'Klass'

    meth = cm1.add_method RDoc::AnyMethod.new(nil, 'm1')
    meth.record_location tl1
    meth = cm1.add_method RDoc::AnyMethod.new(nil, 'm3')
    meth.record_location tl1

    cm2 = RDoc::ClassModule.new 'Klass'
    cm2.store = @store
    cm2.instance_variable_set :@comment, @RM::Document.new

    meth = cm2.add_method RDoc::AnyMethod.new(nil, 'm2')
    meth.record_location tl2
    meth = cm2.add_method RDoc::AnyMethod.new(nil, 'm3')
    meth.record_location tl1
    meth = cm2.add_method RDoc::AnyMethod.new(nil, 'm4')
    meth.record_location tl1

    cm1.merge cm2

    expected = [
      RDoc::AnyMethod.new(nil, 'm2'),
      RDoc::AnyMethod.new(nil, 'm3'),
      RDoc::AnyMethod.new(nil, 'm4'),
    ]

    expected.each do |a| a.parent = cm1 end

    assert_equal expected, cm1.method_list.sort
  end

  def test_merge_methods_version_0
    tl1 = @store.add_file 'one.rb'

    cm1 = tl1.add_class RDoc::NormalClass, 'Klass'

    meth = cm1.add_method RDoc::AnyMethod.new(nil, 'm1')
    meth.record_location tl1
    meth = cm1.add_method RDoc::AnyMethod.new(nil, 'm3')
    meth.record_location tl1

    cm2 = RDoc::ClassModule.new 'Klass'
    cm2.store = @store
    cm2.instance_variable_set :@comment, @RM::Document.new

    meth = cm2.add_method RDoc::AnyMethod.new(nil, 'm2')
    meth = cm2.add_method RDoc::AnyMethod.new(nil, 'm3')
    meth = cm2.add_method RDoc::AnyMethod.new(nil, 'm4')

    cm1.merge cm2

    expected = [
      RDoc::AnyMethod.new(nil, 'm1'),
      RDoc::AnyMethod.new(nil, 'm2'),
      RDoc::AnyMethod.new(nil, 'm3'),
      RDoc::AnyMethod.new(nil, 'm4'),
    ]

    expected.each do |a| a.parent = cm1 end

    assert_equal expected, cm1.method_list.sort
  end

  def test_merge_sections
    store1 = @store

    tl1_1 = store1.add_file 'one.rb'

    cm1  = tl1_1.add_class RDoc::ClassModule, 'Klass'
    cm1.record_location tl1_1

    s1_0 = cm1.sections.first
    s1_1 = cm1.add_section 'section 1', comment('comment 1',   tl1_1)
           cm1.add_section 'section 2', comment('comment 2 a', tl1_1)
           cm1.add_section 'section 4', comment('comment 4 a', tl1_1)

    store2 = RDoc::Store.new
    tl2_1 = store2.add_file 'one.rb'
    tl2_2 = store2.add_file 'two.rb'

    cm2  = tl2_1.add_class RDoc::ClassModule, 'Klass'
    cm2.record_location tl2_1
    cm2.record_location tl2_2

           cm2.sections.first
    s2_2 = cm2.add_section 'section 2', comment('comment 2 b', tl2_1)
    s2_3 = cm2.add_section 'section 3', comment('comment 3',   tl2_2)
           cm2.add_section 'section 4', comment('comment 4 b', tl2_2)

    cm1.merge cm2

    expected = [
      s1_0,
      s1_1,
      s2_2,
      s2_3,
      RDoc::Context::Section.new(cm1, 'section 4', nil)
    ]

    merged_sections = cm1.sections.sort_by do |s|
      s.title || ''
    end

    assert_equal expected, merged_sections

    assert_equal [comment('comment 2 b', tl2_1)],
                 cm1.sections_hash['section 2'].comments

    expected_s4_comments = [
      comment('comment 4 a', tl2_1),
      comment('comment 4 b', tl2_2),
    ]

    assert_equal expected_s4_comments, cm1.sections_hash['section 4'].comments
  end

  def test_merge_sections_overlap
    store1 = @store

    tl1_1 = store1.add_file 'one.rb'
    tl1_3 = store1.add_file 'three.rb'

    cm1  = tl1_1.add_class RDoc::ClassModule, 'Klass'
    cm1.record_location tl1_1

    cm1.add_section 'section', comment('comment 1 a', tl1_1)
    cm1.add_section 'section', comment('comment 3',   tl1_3)

    store2 = RDoc::Store.new
    tl2_1 = store2.add_file 'one.rb'
    tl2_2 = store2.add_file 'two.rb'
    tl2_3 = store2.add_file 'three.rb'

    cm2  = tl2_1.add_class RDoc::ClassModule, 'Klass'
    cm2.record_location tl2_1
    cm2.record_location tl2_2

    s2_0 = cm2.sections.first
    s2_1 = cm2.add_section 'section', comment('comment 1 b', tl1_1)
           cm2.add_section 'section', comment('comment 2',   tl2_2)

    cm1.merge_sections cm2

    expected = [
      s2_0,
      s2_1,
    ]

    merged_sections = cm1.sections.sort_by do |s|
      s.title || ''
    end

    assert_equal expected, merged_sections

    expected = [
      comment('comment 1 b', tl2_1),
      comment('comment 3',   tl2_3),
      comment('comment 2',   tl2_2),
    ]

    comments = cm1.sections_hash['section'].comments

    assert_equal expected, comments.sort_by { |c| c.file.name }
  end

  def test_parse
    tl1 = @store.add_file 'one.rb'
    tl2 = @store.add_file 'two.rb'

    cm = RDoc::ClassModule.new 'Klass'
    cm.add_comment 'comment 1', tl1
    cm.add_comment 'comment 2', tl2

    doc1 = @RM::Document.new @RM::Paragraph.new 'comment 1'
    doc1.file = tl1
    doc2 = @RM::Document.new @RM::Paragraph.new 'comment 2'
    doc2.file = tl2

    expected = @RM::Document.new doc1, doc2

    assert_equal expected, cm.parse(cm.comment_location)
  end

  def test_parse_comment
    tl1 = @store.add_file 'one.rb'

    cm = RDoc::ClassModule.new 'Klass'
    cm.comment = comment 'comment 1', tl1

    doc = @RM::Document.new @RM::Paragraph.new 'comment 1'
    doc.file = tl1

    assert_equal doc, cm.parse(cm.comment)
  end

  def test_parse_comment_format
    tl1 = @store.add_file 'one.rb'

    cm = RDoc::ClassModule.new 'Klass'
    cm.comment = comment 'comment ((*1*))', tl1
    cm.comment.format = 'rd'

    doc = @RM::Document.new @RM::Paragraph.new 'comment <em>1</em>'
    doc.file = tl1

    assert_equal doc, cm.parse(cm.comment)
  end

  def test_parse_comment_location
    tl1 = @store.add_file 'one.rb'
    tl2 = @store.add_file 'two.rb'

    cm = tl1.add_class RDoc::NormalClass, 'Klass'
    cm.add_comment 'comment 1', tl1
    cm.add_comment 'comment 2', tl2

    cm = Marshal.load Marshal.dump cm

    doc1 = @RM::Document.new @RM::Paragraph.new 'comment 1'
    doc1.file = tl1
    doc2 = @RM::Document.new @RM::Paragraph.new 'comment 2'
    doc2.file = tl2

    assert_same cm.comment_location, cm.parse(cm.comment_location)
  end

  def test_remove_nodoc_children
    parent = @top_level.add_class RDoc::ClassModule, 'A'
    parent.modules_hash.replace 'B' => true, 'C' => true
    @store.modules_hash.replace 'A::B' => true

    parent.classes_hash.replace 'D' => true, 'E' => true
    @store.classes_hash.replace 'A::D' => true

    parent.remove_nodoc_children

    assert_equal %w[B], parent.modules_hash.keys
    assert_equal %w[D], parent.classes_hash.keys
  end

  def test_search_record
    @c2_c3.add_comment 'This is a comment.', @xref_data

    expected = [
      'C3',
      'C2::C3',
      'C2::C3',
      '',
      'C2/C3.html',
      '',
      "<p>This is a comment.\n"
    ]

    assert_equal expected, @c2_c3.search_record
  end

  def test_search_record_merged
    @c2_c3.add_comment 'comment A', @store.add_file('a.rb')
    @c2_c3.add_comment 'comment B', @store.add_file('b.rb')

    expected = [
      'C3',
      'C2::C3',
      'C2::C3',
      '',
      'C2/C3.html',
      '',
      "<p>comment A\n<p>comment B\n"
    ]

    assert_equal expected, @c2_c3.search_record
  end

  def test_store_equals
    # version 2
    loaded = Marshal.load "\x04\bU:\x16RDoc::NormalClass[\x0Fi\aI\"\nKlass" +
                          "\x06:\x06EFI\"\x15Namespace::Klass\x06;\x06FI" +
                          "\"\nSuper\x06;\x06Fo:\eRDoc::Markup::Document\a" +
                          ":\v@parts[\x06o;\a\a;\b[\x06o" +
                          ":\x1CRDoc::Markup::Paragraph\x06;\b" +
                          "[\x06I\"\x16this is a comment\x06;\x06F" +
                          ":\n@fileI\"\ffile.rb\x06;\x06F;\n0[\a[\nI" +
                          "\"\aa2\x06;\x06FI\"\aRW\x06;\x06F:\vpublicT@\x11" +
                          "[\nI\"\aa1\x06;\x06FI\"\aRW\x06;\x06F;\vF@\x11" +
                          "[\x06[\bI\"\aC1\x06;\x06Fo;\a\a;\b[\x00;\n0@\x11" +
                          "[\x06[\bI\"\aI1\x06;\x06Fo;\a\a;\b[\x00;\n0@\x11" +
                          "[\a[\aI\"\nclass\x06;\x06F[\b[\a;\v[\x00" +
                          "[\a:\x0Eprotected[\x00[\a:\fprivate[\x00[\aI" +
                          "\"\rinstance\x06;\x06F[\b[\a;\v[\x06[\aI" +
                          "\"\am1\x06;\x06F@\x11[\a;\f[\x00[\a;\r[\x00" +
                          "[\x06[\bI\"\aE1\x06;\x06Fo;\a\a;\b[\x00;\n0@\x11"

    loaded.store = @store

    assert_same @store, loaded.store

    a = loaded.attributes.first
    assert_same @store, a.store
    assert_same @store, a.file.store

    c = loaded.constants.first
    assert_same @store, c.store
    assert_same @store, c.file.store

    i = loaded.includes.first
    assert_same @store, i.store
    assert_same @store, i.file.store

    e = loaded.extends.first
    assert_same @store, e.store
    assert_same @store, e.file.store

    m = loaded.method_list.first
    assert_same @store, m.store
    assert_same @store, m.file.store
  end

  def test_superclass
    assert_equal @c3_h1, @c3_h2.superclass
  end

  def test_update_aliases_class
    n1 = @xref_data.add_module RDoc::NormalClass, 'N1'
    n1_k2 = n1.add_module RDoc::NormalClass, 'N2'

    n1.add_module_alias n1_k2, 'A1', @xref_data

    n1_a1_c = n1.constants.find { |c| c.name == 'A1' }
    refute_nil n1_a1_c
    assert_equal n1_k2, n1_a1_c.is_alias_for, 'sanity check'

    n1.update_aliases

    n1_a1_k = @xref_data.find_class_or_module 'N1::A1'
    refute_nil n1_a1_k
    assert_equal n1_k2, n1_a1_k.is_alias_for
    refute_equal n1_k2, n1_a1_k

    assert_equal 1, n1_k2.aliases.length
    assert_equal n1_a1_k, n1_k2.aliases.first

    assert_equal 'N1::N2', n1_k2.full_name
    assert_equal 'N1::A1', n1_a1_k.full_name
  end

  def test_update_aliases_module
    n1 = @xref_data.add_module RDoc::NormalModule, 'N1'
    n1_n2 = n1.add_module RDoc::NormalModule, 'N2'

    n1.add_module_alias n1_n2, 'A1', @xref_data

    n1_a1_c = n1.constants.find { |c| c.name == 'A1' }
    refute_nil n1_a1_c
    assert_equal n1_n2, n1_a1_c.is_alias_for, 'sanity check'

    n1.update_aliases

    n1_a1_m = @xref_data.find_class_or_module 'N1::A1'
    refute_nil n1_a1_m
    assert_equal n1_n2, n1_a1_m.is_alias_for
    refute_equal n1_n2, n1_a1_m

    assert_equal 1, n1_n2.aliases.length
    assert_equal n1_a1_m, n1_n2.aliases.first

    assert_equal 'N1::N2', n1_n2.full_name
    assert_equal 'N1::A1', n1_a1_m.full_name
  end

  def test_update_aliases_reparent
    l1 = @xref_data.add_module RDoc::NormalModule, 'L1'
    l1_l2 = l1.add_module RDoc::NormalModule, 'L2'
    o1 = @xref_data.add_module RDoc::NormalModule, 'O1'

    o1.add_module_alias l1_l2, 'A1', @xref_data

    o1_a1_c = o1.constants.find { |c| c.name == 'A1' }
    refute_nil o1_a1_c
    assert_equal l1_l2, o1_a1_c.is_alias_for
    refute_equal l1_l2, o1_a1_c

    o1.update_aliases

    o1_a1_m = @xref_data.find_class_or_module 'O1::A1'
    refute_nil o1_a1_m
    assert_equal l1_l2, o1_a1_m.is_alias_for

    assert_equal 1, l1_l2.aliases.length
    assert_equal o1_a1_m, l1_l2.aliases[0]

    assert_equal 'L1::L2', l1_l2.full_name
    assert_equal 'O1::A1', o1_a1_m.full_name
  end

  def test_update_aliases_reparent_root
    store = RDoc::Store.new

    top_level = store.add_file 'file.rb'

    klass  = top_level.add_class RDoc::NormalClass, 'Klass'
    object = top_level.add_class RDoc::NormalClass, 'Object'

    const = RDoc::Constant.new 'A', nil, ''
    const.record_location top_level
    const.is_alias_for = klass

    top_level.add_module_alias klass, 'A', top_level

    object.add_constant const

    object.update_aliases

    assert_equal %w[A Klass Object], store.classes_hash.keys.sort

    assert_equal 'A',     store.classes_hash['A'].full_name
    assert_equal 'Klass', store.classes_hash['Klass'].full_name
  end

  def test_update_includes
    a = RDoc::Include.new 'M1', nil
    b = RDoc::Include.new 'M2', nil
    c = RDoc::Include.new 'C', nil

    @c1.add_include a
    @c1.add_include b
    @c1.add_include c
    @c1.ancestors # cache included modules

    @m1_m2.document_self = nil
    assert @m1_m2.remove_from_documentation?

    assert @store.modules_hash.key? @m1_m2.full_name
    refute @store.modules_hash[@m1_m2.full_name].nil?

    @store.remove_nodoc @store.modules_hash
    refute @store.modules_hash.key? @m1_m2.full_name

    @c1.update_includes

    assert_equal [a, c], @c1.includes
  end

  def test_update_includes_trim
    a = RDoc::Include.new 'D::M', nil
    b = RDoc::Include.new 'D::M', nil

    @c1.add_include a
    @c1.add_include b
    @c1.ancestors # cache included modules

    @c1.update_includes

    assert_equal [a], @c1.includes
  end

  def test_update_includes_with_colons
    a = RDoc::Include.new 'M1', nil
    b = RDoc::Include.new 'M1::M2', nil
    c = RDoc::Include.new 'C', nil

    @c1.add_include a
    @c1.add_include b
    @c1.add_include c
    @c1.ancestors # cache included modules

    @m1_m2.document_self = nil
    assert @m1_m2.remove_from_documentation?

    assert @store.modules_hash.key? @m1_m2.full_name
    refute @store.modules_hash[@m1_m2.full_name].nil?
    @store.remove_nodoc @store.modules_hash
    refute @store.modules_hash.key? @m1_m2.full_name

    @c1.update_includes

    assert_equal [a, c], @c1.includes
  end

  def test_update_extends
    a = RDoc::Extend.new 'M1', nil
    b = RDoc::Extend.new 'M2', nil
    c = RDoc::Extend.new 'C', nil

    @c1.add_extend a
    @c1.add_extend b
    @c1.add_extend c
    @c1.each_extend do |extend| extend.module end # cache extended modules

    @m1_m2.document_self = nil
    assert @m1_m2.remove_from_documentation?

    assert @store.modules_hash.key? @m1_m2.full_name
    refute @store.modules_hash[@m1_m2.full_name].nil?
    @store.remove_nodoc @store.modules_hash
    refute @store.modules_hash.key? @m1_m2.full_name

    @c1.update_extends

    assert_equal [a, b, c], @c1.extends
  end

  def test_update_extends_trim
    a = RDoc::Extend.new 'D::M', nil
    b = RDoc::Extend.new 'D::M', nil

    @c1.add_extend a
    @c1.add_extend b
    @c1.each_extend do |extend| extend.module end # cache extended modules

    @c1.update_extends

    assert_equal [a], @c1.extends
  end

  def test_update_extends_with_colons
    a = RDoc::Extend.new 'M1', nil
    b = RDoc::Extend.new 'M1::M2', nil
    c = RDoc::Extend.new 'C', nil

    @c1.add_extend a
    @c1.add_extend b
    @c1.add_extend c
    @c1.each_extend do |extend| extend.module end # cache extended modules

    @m1_m2.document_self = nil
    assert @m1_m2.remove_from_documentation?

    assert @store.modules_hash.key? @m1_m2.full_name
    refute @store.modules_hash[@m1_m2.full_name].nil?

    @store.remove_nodoc @store.modules_hash
    refute @store.modules_hash.key? @m1_m2.full_name

    @c1.update_extends

    assert_equal [a, c], @c1.extends
  end

end

