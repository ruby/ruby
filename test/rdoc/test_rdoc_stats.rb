# frozen_string_literal: true
require_relative 'helper'

class TestRDocStats < RDoc::TestCase

  def setup
    super

    @s = RDoc::Stats.new @store, 0

    @tl = @store.add_file 'file.rb'
    @tl.parser = RDoc::Parser::Ruby
  end

  def test_doc_stats
    c = RDoc::CodeObject.new

    assert_equal [1, 1], @s.doc_stats([c])
  end

  def test_doc_stats_documented
    c = RDoc::CodeObject.new
    c.comment = comment 'x'

    assert_equal [1, 0], @s.doc_stats([c])
  end

  def test_doc_stats_display_eh
    c = RDoc::CodeObject.new
    c.ignore

    assert_equal [0, 0], @s.doc_stats([c])
  end

  def test_report_attr
    c = @tl.add_class RDoc::NormalClass, 'C'
    c.record_location @tl
    c.add_comment 'C', @tl

    a = RDoc::Attr.new nil, 'a', 'RW', nil
    a.record_location @tl
    c.add_attribute a

    @store.complete :public

    report = @s.report

    expected =
      doc(
        para('The following items are not documented:'),
        blank_line,
        verb(
          "class C # is documented\n",
          "\n",
          "  attr_accessor :a # in file file.rb\n",
          "\n",
          "end\n"),
        blank_line)

    assert_equal expected, report
  end

  def test_report_attr_documented
    c = @tl.add_class RDoc::NormalClass, 'C'
    c.record_location @tl
    c.add_comment 'C', @tl

    a = RDoc::Attr.new nil, 'a', 'RW', 'a'
    a.record_location @tl
    c.add_attribute a

    @store.complete :public

    report = @s.report

    assert_equal @s.great_job, report
  end

  def test_report_attr_line
    c = @tl.add_class RDoc::NormalClass, 'C'
    c.record_location @tl
    c.add_comment 'C', @tl

    a = RDoc::Attr.new nil, 'a', 'RW', nil
    a.record_location @tl
    a.line = 3
    c.add_attribute a

    @store.complete :public

    assert_match '# in file file.rb:3', @s.report.accept(to_rdoc)
  end

  def test_report_constant
    m = @tl.add_module RDoc::NormalModule, 'M'
    m.record_location @tl
    m.add_comment 'M', @tl

    c = RDoc::Constant.new 'C', nil, nil
    c.record_location @tl
    m.add_constant c

    @store.complete :public

    report = @s.report

    expected =
      doc(
        para('The following items are not documented:'),
        blank_line,
        verb(
          "module M # is documented\n",
          "\n",
          "  # in file file.rb\n",
          "  C = nil\n",
          "\n",
          "end\n"),
        blank_line)

    assert_equal expected, report
  end

  def test_report_constant_alias
    mod = @tl.add_module RDoc::NormalModule, 'M'

    c = @tl.add_class RDoc::NormalClass, 'C'
    mod.add_constant c

    ca = RDoc::Constant.new 'CA', nil, nil
    ca.is_alias_for = c

    @tl.add_constant ca

    @store.complete :public

    report = @s.report

    # TODO change this to refute match, aliases should be ignored as they are
    # programmer convenience constructs
    assert_match 'class Object', report.accept(to_rdoc)
  end

  def test_report_constant_documented
    m = @tl.add_module RDoc::NormalModule, 'M'
    m.record_location @tl
    m.add_comment 'M', @tl

    c = RDoc::Constant.new 'C', nil, 'C'
    c.record_location @tl
    m.add_constant c

    @store.complete :public

    report = @s.report

    assert_equal @s.great_job, report
  end

  def test_report_constant_line
    m = @tl.add_module RDoc::NormalModule, 'M'
    m.record_location @tl
    m.add_comment 'M', @tl

    c = RDoc::Constant.new 'C', nil, nil
    c.record_location @tl
    c.line = 5
    m.add_constant c

    @store.complete :public

    assert_match '# in file file.rb:5', @s.report.accept(to_rdoc)
  end

  def test_report_class
    c = @tl.add_class RDoc::NormalClass, 'C'
    c.record_location @tl

    m = RDoc::AnyMethod.new nil, 'm'
    m.record_location @tl
    c.add_method m
    m.comment = 'm'

    @store.complete :public

    report = @s.report

    expected =
      doc(
        para('The following items are not documented:'),
        blank_line,
        para('In files:'),
        list(:BULLET, *[
          item(nil, para('file.rb'))]),
        blank_line,
        verb("class C\n", "end\n"),
        blank_line)

    assert_equal expected, report
  end

  def test_report_skip_object
    c = @tl.add_class RDoc::NormalClass, 'Object'
    c.record_location @tl

    m = RDoc::AnyMethod.new nil, 'm'
    m.record_location @tl
    c.add_method m
    m.comment = 'm'

    @store.complete :public

    refute_match %r%^class Object$%, @s.report.accept(to_rdoc)
  end

  def test_report_class_documented
    c = @tl.add_class RDoc::NormalClass, 'C'
    c.record_location @tl
    c.add_comment 'C', @tl

    m = RDoc::AnyMethod.new nil, 'm'
    m.record_location @tl
    c.add_method m
    m.comment = 'm'

    @store.complete :public

    report = @s.report

    assert_equal @s.great_job, report
  end

  def test_report_class_documented_level_1
    c1 = @tl.add_class RDoc::NormalClass, 'C1'
    c1.record_location @tl
    c1.add_comment 'C1', @tl

    m1 = RDoc::AnyMethod.new nil, 'm1'
    m1.record_location @tl
    c1.add_method m1
    m1.comment = 'm1'

    c2 = @tl.add_class RDoc::NormalClass, 'C2'
    c2.record_location @tl

    m2 = RDoc::AnyMethod.new nil, 'm2'
    m2.record_location @tl
    c2.add_method m2
    m2.comment = 'm2'

    @store.complete :public

    @s.coverage_level = 1

    report = @s.report

    expected =
      doc(
        para('The following items are not documented:'),
        blank_line,
        para('In files:'),
        list(:BULLET, *[
          item(nil, para('file.rb'))]),
        blank_line,
        verb("class C2\n", "end\n"),
        blank_line)

    assert_equal expected, report
  end

  def test_report_class_empty
    @tl.add_class RDoc::NormalClass, 'C'

    @store.complete :public

    report = @s.report

    expected =
      doc(
        para('The following items are not documented:'),
        blank_line,
        para('class C is referenced but empty.'),
        para("It probably came from another project.  I'm sorry I'm holding it against you."),
        blank_line)

    assert_equal expected, report
  end

  def test_report_class_empty_2
    c1 = @tl.add_class RDoc::NormalClass, 'C1'
    c1.record_location @tl

    c2 = @tl.add_class RDoc::NormalClass, 'C2'
    c2.record_location @tl
    c2.add_comment 'C2', @tl

    @store.complete :public

    @s.coverage_level = 1
    report = @s.report

    expected =
      doc(
        para('The following items are not documented:'),
        blank_line,
        para('In files:'),
        list(:BULLET, *[
          item(nil, para('file.rb'))]),
        blank_line,
        verb("class C1\n", "end\n"),
        blank_line)

    assert_equal expected, report
  end

  def test_report_class_method_documented
    c = @tl.add_class RDoc::NormalClass, 'C'
    c.record_location @tl

    m = RDoc::AnyMethod.new nil, 'm'
    m.record_location @tl
    c.add_method m
    m.comment = 'm'

    @store.complete :public

    report = @s.report

    expected =
      doc(
        para('The following items are not documented:'),
        blank_line,
        para('In files:'),
        list(:BULLET, *[
          item(nil, para('file.rb'))]),
        blank_line,
        verb("class C\n", "end\n"),
        blank_line)

    assert_equal expected, report
  end

  def test_report_class_module_ignore
    c = @tl.add_class RDoc::NormalClass, 'C'
    c.ignore

    @store.complete :public

    report = @s.report_class_module c

    assert_nil report
  end

  def test_report_empty
    @store.complete :public

    report = @s.report

    assert_equal @s.great_job, report
  end

  def test_report_method
    c = @tl.add_class RDoc::NormalClass, 'C'
    c.record_location @tl
    c.add_comment 'C', @tl

    m1 = RDoc::AnyMethod.new nil, 'm1'
    m1.record_location @tl
    c.add_method m1

    m2 = RDoc::AnyMethod.new nil, 'm2'
    m2.record_location @tl
    c.add_method m2
    m2.comment = 'm2'

    @store.complete :public

    report = @s.report

    expected =
      doc(
        para('The following items are not documented:'),
        blank_line,
        verb(*[
          "class C # is documented\n",
          "\n",
          "  # in file file.rb\n",
          "  def m1; end\n",
          "\n",
          "end\n"]),
        blank_line)

    assert_equal expected, report
  end

  def test_report_method_class
    c = @tl.add_class RDoc::NormalClass, 'C'
    c.record_location @tl
    c.add_comment 'C', @tl

    m1 = RDoc::AnyMethod.new nil, 'm1'
    m1.record_location @tl
    m1.singleton = true
    c.add_method m1

    m2 = RDoc::AnyMethod.new nil, 'm2'
    m2.record_location @tl
    m2.singleton = true
    c.add_method m2
    m2.comment = 'm2'

    @store.complete :public

    report = @s.report

    expected =
      doc(
        para('The following items are not documented:'),
        blank_line,
        verb(*[
          "class C # is documented\n",
          "\n",
          "  # in file file.rb\n",
          "  def self.m1; end\n",
          "\n",
          "end\n"]),
        blank_line)

    assert_equal expected, report
  end

  def test_report_method_documented
    c = @tl.add_class RDoc::NormalClass, 'C'
    c.record_location @tl
    c.add_comment 'C', @tl

    m = RDoc::AnyMethod.new nil, 'm'
    m.record_location @tl
    c.add_method m
    m.comment = 'm'

    @store.complete :public

    report = @s.report

    assert_equal @s.great_job, report
  end

  def test_report_method_line
    c = @tl.add_class RDoc::NormalClass, 'C'
    c.record_location @tl
    c.add_comment 'C', @tl

    m1 = RDoc::AnyMethod.new nil, 'm1'
    m1.record_location @tl
    m1.line = 4
    c.add_method m1

    @store.complete :public

    assert_match '# in file file.rb:4', @s.report.accept(to_rdoc)
  end

  def test_report_method_parameters
    c = @tl.add_class RDoc::NormalClass, 'C'
    c.record_location @tl
    c.add_comment 'C', @tl

    m1 = RDoc::AnyMethod.new nil, 'm1'
    m1.record_location @tl
    m1.params = '(p1, p2)'
    m1.comment = 'Stuff with +p1+'
    c.add_method m1

    m2 = RDoc::AnyMethod.new nil, 'm2'
    m2.record_location @tl
    c.add_method m2
    m2.comment = 'm2'

    @store.complete :public

    @s.coverage_level = 1
    report = @s.report

    expected =
      doc(
        para('The following items are not documented:'),
        blank_line,
        verb(*[
          "class C # is documented\n",
          "\n",
          "  # in file file.rb\n",
          "  # +p2+ is not documented\n",
          "  def m1(p1, p2); end\n",
          "\n",
          "end\n"]),
        blank_line)

    assert_equal expected, report
  end

  def test_report_method_parameters_documented
    @tl.parser = RDoc::Parser::Ruby
    c = @tl.add_class RDoc::NormalClass, 'C'
    c.record_location @tl
    c.add_comment 'C', @tl

    m = RDoc::AnyMethod.new nil, 'm'
    m.record_location @tl
    m.params = '(p1)'
    m.comment = 'Stuff with +p1+'
    c.add_method m

    @store.complete :public

    @s.coverage_level = 1
    report = @s.report

    assert_equal @s.great_job, report
  end

  def test_report_method_parameters_yield
    c = @tl.add_class RDoc::NormalClass, 'C'
    c.record_location @tl
    c.add_comment 'C', @tl

    m = RDoc::AnyMethod.new nil, 'm'
    m.record_location @tl
    m.call_seq = <<-SEQ
m(a) { |c| ... }
m(a, b) { |c, d| ... }
    SEQ
    m.comment = 'Stuff with +a+, yields +c+ for you to do stuff with'
    c.add_method m

    @store.complete :public

    @s.coverage_level = 1
    report = @s.report

    expected =
      doc(
        para('The following items are not documented:'),
        blank_line,
        verb(
          "class C # is documented\n",
          "\n",
          "  # in file file.rb\n",
          "  # +b+, +d+ is not documented\n",
          "  def m; end\n",
          "\n",
          "end\n"),
        blank_line)

    assert_equal expected, report
  end

  def test_summary
    c = @tl.add_class RDoc::NormalClass, 'C'
    c.record_location @tl

    m = @tl.add_module RDoc::NormalModule, 'M'
    m.record_location @tl

    a = RDoc::Attr.new nil, 'a', 'RW', nil
    a.record_location @tl
    c.add_attribute a

    c_c = RDoc::Constant.new 'C', nil, nil
    c_c.record_location @tl
    c.add_constant c_c

    m = RDoc::AnyMethod.new nil, 'm'
    m.record_location @tl
    c.add_method m

    @store.complete :public

    summary = @s.summary.accept to_rdoc
    summary.sub!(/  Elapsed:.*/m, '')

    expected = <<-EXPECTED
  Files:      0

  Classes:    1 (1 undocumented)
  Modules:    1 (1 undocumented)
  Constants:  1 (1 undocumented)
  Attributes: 1 (1 undocumented)
  Methods:    1 (1 undocumented)

  Total:      5 (5 undocumented)
    0.00% documented

    EXPECTED

    assert_equal summary, expected
  end

  def test_summary_level_false
    c = @tl.add_class RDoc::NormalClass, 'C'
    c.record_location @tl

    @store.complete :public

    @s.coverage_level = false

    summary = @s.summary.accept to_rdoc
    summary.sub!(/  Elapsed:.*/m, '')

    expected = <<-EXPECTED
  Files:      0

  Classes:    1 (1 undocumented)
  Modules:    0 (0 undocumented)
  Constants:  0 (0 undocumented)
  Attributes: 0 (0 undocumented)
  Methods:    0 (0 undocumented)

  Total:      1 (1 undocumented)
    0.00% documented

    EXPECTED

    assert_equal summary, expected
  end

  def test_summary_level_1
    c = @tl.add_class RDoc::NormalClass, 'C'
    c.record_location @tl
    c.add_comment 'C', @tl

    m = RDoc::AnyMethod.new nil, 'm'
    m.record_location @tl
    m.params = '(p1, p2)'
    m.comment = 'Stuff with +p1+'
    c.add_method m

    @store.complete :public

    @s.coverage_level = 1
    @s.report

    summary = @s.summary.accept to_rdoc
    summary.sub!(/  Elapsed:.*/m, '')

    expected = <<-EXPECTED
  Files:      0

  Classes:    1 (0 undocumented)
  Modules:    0 (0 undocumented)
  Constants:  0 (0 undocumented)
  Attributes: 0 (0 undocumented)
  Methods:    1 (0 undocumented)
  Parameters: 2 (1 undocumented)

  Total:      4 (1 undocumented)
   75.00% documented

    EXPECTED

    assert_equal summary, expected
  end

  def to_rdoc
    RDoc::Markup::ToRdoc.new
  end

  def test_undoc_params
    method = RDoc::AnyMethod.new [], 'm'
    method.params = '(a)'
    method.comment = comment 'comment'

    total, undoc = @s.undoc_params method

    assert_equal 1,     total
    assert_equal %w[a], undoc
  end

  def test_undoc_params_block
    method = RDoc::AnyMethod.new [], 'm'
    method.params = '(&a)'
    method.comment = comment '+a+'

    total, undoc = @s.undoc_params method

    assert_equal 1, total
    assert_empty    undoc
  end

  def test_undoc_params_documented
    method = RDoc::AnyMethod.new [], 'm'
    method.params = '(a)'
    method.comment = comment '+a+'

    total, undoc = @s.undoc_params method

    assert_equal 1, total
    assert_empty    undoc
  end

  def test_undoc_params_keywords
    method = RDoc::AnyMethod.new [], 'm'
    method.params = '(**a)'
    method.comment = comment '+a+'

    total, undoc = @s.undoc_params method

    assert_equal 1, total
    assert_empty    undoc
  end

  def test_undoc_params_splat
    method = RDoc::AnyMethod.new [], 'm'
    method.params = '(*a)'
    method.comment = comment '+a+'

    total, undoc = @s.undoc_params method

    assert_equal 1, total
    assert_empty    undoc
  end

end

