require File.expand_path '../xref_test_case', __FILE__

class TestRDocClassModule < XrefTestCase

  def setup
    super

    @RM = RDoc::Markup
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

  # handle making a short module alias of yourself

  def test_find_class_named
    @c2.classes_hash['C2'] = @c2

    assert_nil @c2.find_class_named('C1')
  end

  def test_merge
    cm1 = RDoc::ClassModule.new 'Klass'
    cm1.comment = 'klass 1'
    cm1.add_attribute RDoc::Attr.new(nil, 'a1', 'RW', '')
    cm1.add_attribute RDoc::Attr.new(nil, 'a3', 'R', '')
    cm1.add_constant RDoc::Constant.new('C1', nil, '')
    cm1.add_include RDoc::Include.new('I1', '')
    cm1.add_method RDoc::AnyMethod.new(nil, 'm1')

    cm2 = RDoc::ClassModule.new 'Klass'
    cm2.instance_variable_set(:@comment,
                              @RM::Document.new(
                                @RM::Paragraph.new('klass 2')))
    cm2.add_attribute RDoc::Attr.new(nil, 'a2', 'RW', '')
    cm2.add_attribute RDoc::Attr.new(nil, 'a3', 'W', '')
    cm2.add_constant RDoc::Constant.new('C2', nil, '')
    cm2.add_include RDoc::Include.new('I2', '')
    cm2.add_method RDoc::AnyMethod.new(nil, 'm2')

    cm1.merge cm2

    document = @RM::Document.new(
      @RM::Paragraph.new('klass 2'),
      @RM::Paragraph.new('klass 1'))

    assert_equal document, cm1.comment

    expected = [
      RDoc::Attr.new(nil, 'a1', 'RW', ''),
      RDoc::Attr.new(nil, 'a2', 'RW', ''),
      RDoc::Attr.new(nil, 'a3', 'RW', ''),
    ]

    expected.each do |a| a.parent = cm1 end
    assert_equal expected, cm1.attributes.sort

    expected = [
      RDoc::Constant.new('C1', nil, ''),
      RDoc::Constant.new('C2', nil, ''),
    ]

    expected.each do |c| c.parent = cm1 end
    assert_equal expected, cm1.constants.sort

    expected = [
      RDoc::Include.new('I1', ''),
      RDoc::Include.new('I2', ''),
    ]

    expected.each do |i| i.parent = cm1 end
    assert_equal expected, cm1.includes.sort

    expected = [
      RDoc::AnyMethod.new(nil, 'm1'),
      RDoc::AnyMethod.new(nil, 'm2'),
    ]

    expected.each do |m| m.parent = cm1 end
    assert_equal expected, cm1.method_list.sort
  end

  def test_superclass
    assert_equal @c3_h1, @c3_h2.superclass
  end

end

