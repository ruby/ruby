# frozen_string_literal: true
require_relative 'helper'

class TestRDocRIDriver < RDoc::TestCase

  def setup
    super

    @tmpdir = File.join Dir.tmpdir, "test_rdoc_ri_driver_#{$$}"
    @home_ri = File.join @tmpdir, 'dot_ri'

    FileUtils.mkdir_p @tmpdir
    FileUtils.mkdir_p @home_ri

    @orig_ri = ENV['RI']
    ENV['HOME'] = @tmpdir
    @rdoc_home = File.join ENV["HOME"], ".rdoc"
    FileUtils.mkdir_p @rdoc_home
    ENV.delete 'RI'

    @options = RDoc::RI::Driver.default_options
    @options[:use_system] = false
    @options[:use_site]   = false
    @options[:use_home]   = false
    @options[:use_gems]   = false

    @options[:home]       = @tmpdir
    @options[:use_stdout] = true
    @options[:formatter]  = @RM::ToRdoc

    @driver = RDoc::RI::Driver.new @options
  end

  def teardown
    ENV['RI'] = @orig_ri
    FileUtils.rm_rf @tmpdir

    super
  end

  DUMMY_PAGER = ":;\n"

  def with_dummy_pager
    pager_env, ENV['RI_PAGER'] = ENV['RI_PAGER'], DUMMY_PAGER
    yield
  ensure
    ENV['RI_PAGER'] = pager_env
  end

  def test_self_dump
    util_store

    out, = capture_output do
      RDoc::RI::Driver.dump @store1.cache_path
    end

    assert_match %r%:class_methods%,    out
    assert_match %r%:modules%,          out
    assert_match %r%:instance_methods%, out
    assert_match %r%:ancestors%,        out
  end

  def test_add_also_in_empty
    out = @RM::Document.new

    @driver.add_also_in out, []

    assert_empty out
  end

  def test_add_also_in
    util_multi_store
    @store1.type = :system
    @store2.type = :home

    out = @RM::Document.new

    @driver.add_also_in out, [@store1, @store2]

    expected = @RM::Document.new(
      @RM::Rule.new(1),
      @RM::Paragraph.new('Also found in:'),
      @RM::Verbatim.new("ruby core", "\n",
                        @rdoc_home, "\n"))

    assert_equal expected, out
  end

  def test_add_class
    util_multi_store

    out = @RM::Document.new

    @driver.add_class out, 'Bar', [@cBar]

    expected = @RM::Document.new(
      @RM::Heading.new(1, 'Bar < Foo'),
      @RM::BlankLine.new)

    assert_equal expected, out
  end

  def test_add_from
    util_store
    @store1.type = :system

    out = @RM::Document.new

    @driver.add_from out, @store1

    expected = @RM::Document.new @RM::Paragraph.new("(from ruby core)")

    assert_equal expected, out
  end

  def test_add_extends
    util_store

    out = @RM::Document.new

    @driver.add_extends out, [[[@cFooExt], @store1]]

    expected = @RM::Document.new(
      @RM::Rule.new(1),
      @RM::Heading.new(1, "Extended by:"),
      @RM::Paragraph.new("Ext (from #{@store1.friendly_path})"),
      @RM::BlankLine.new,
      @RM::Paragraph.new("Extend thingy"),
      @RM::BlankLine.new)

    assert_equal expected, out
  end

  def test_add_extension_modules_empty
    out = @RM::Document.new

    @driver.add_extension_modules out, 'Includes', []

    assert_empty out
  end

  def test_add_extension_modules_many
    util_store

    out = @RM::Document.new

    enum = RDoc::Include.new 'Enumerable', nil
    @cFoo.add_include enum

    @driver.add_extension_modules out, 'Includes', [[[@cFooInc, enum], @store1]]

    expected = @RM::Document.new(
      @RM::Rule.new(1),
      @RM::Heading.new(1, "Includes:"),
      @RM::Paragraph.new("(from #{@store1.friendly_path})"),
      @RM::BlankLine.new,
      @RM::Paragraph.new("Inc"),
      @RM::BlankLine.new,
      @RM::Paragraph.new("Include thingy"),
      @RM::BlankLine.new,
      @RM::Verbatim.new("Enumerable", "\n"))

    assert_equal expected, out
  end

  def test_add_extension_modules_many_no_doc
    util_store

    out = @RM::Document.new

    enum = RDoc::Include.new 'Enumerable', nil
    @cFoo.add_include enum
    @cFooInc.instance_variable_set :@comment, ''

    @driver.add_extension_modules out, 'Includes', [[[@cFooInc, enum], @store1]]

    expected = @RM::Document.new(
      @RM::Rule.new(1),
      @RM::Heading.new(1, "Includes:"),
      @RM::Paragraph.new("(from #{@store1.friendly_path})"),
      @RM::Verbatim.new("Inc", "\n",
                        "Enumerable", "\n"))

    assert_equal expected, out
  end

  def test_add_extension_modules_one
    util_store

    out = @RM::Document.new

    @driver.add_extension_modules out, 'Includes', [[[@cFooInc], @store1]]

    expected = @RM::Document.new(
      @RM::Rule.new(1),
      @RM::Heading.new(1, "Includes:"),
      @RM::Paragraph.new("Inc (from #{@store1.friendly_path})"),
      @RM::BlankLine.new,
      @RM::Paragraph.new("Include thingy"),
      @RM::BlankLine.new)

    assert_equal expected, out
  end

  def test_add_includes
    util_store

    out = @RM::Document.new

    @driver.add_includes out, [[[@cFooInc], @store1]]

    expected = @RM::Document.new(
      @RM::Rule.new(1),
      @RM::Heading.new(1, "Includes:"),
      @RM::Paragraph.new("Inc (from #{@store1.friendly_path})"),
      @RM::BlankLine.new,
      @RM::Paragraph.new("Include thingy"),
      @RM::BlankLine.new)

    assert_equal expected, out
  end

  def test_add_method
    util_store

    out = doc

    @driver.add_method out, 'Foo::Bar#blah'

    expected =
      doc(
        head(1, 'Foo::Bar#blah'),
        blank_line,
        para("(from #{@rdoc_home})"),
        head(3, 'Implementation from Bar'),
        rule(1),
        verb("blah(5) => 5\n",
             "blah(6) => 6\n"),
        rule(1),
        blank_line,
        blank_line)

    assert_equal expected, out
  end

  def test_add_method_that_is_alias_for_original
    util_store

    out = doc

    @driver.add_method out, 'Qux#aliased'

    expected =
      doc(
        head(1, 'Qux#aliased'),
        blank_line,
        para("(from #{@rdoc_home})"),
        rule(1),
        blank_line,
        para('alias comment'),
        blank_line,
        blank_line,
        para('(This method is an alias for Qux#original.)'),
        blank_line,
        para('original comment'),
        blank_line,
        blank_line)

    assert_equal expected, out
  end

  def test_add_method_attribute
    util_store

    out = doc

    @driver.add_method out, 'Foo::Bar#attr'

    expected =
      doc(
        head(1, 'Foo::Bar#attr'),
        blank_line,
        para("(from #{@rdoc_home})"),
        rule(1),
        blank_line,
        blank_line)

    assert_equal expected, out
  end

  def test_add_method_inherited
    util_multi_store

    out = doc

    @driver.add_method out, 'Bar#inherit'

    expected =
      doc(
        head(1, 'Bar#inherit'),
        blank_line,
        para("(from #{@rdoc_home})"),
        head(3, 'Implementation from Foo'),
        rule(1),
        blank_line,
        blank_line)

    assert_equal expected, out
  end

  def test_add_method_overridden
    util_multi_store

    out = doc

    @driver.add_method out, 'Bar#override'

    expected =
      doc(
        head(1, 'Bar#override'),
        blank_line,
        para("(from #{@store2.path})"),
        rule(1),
        blank_line,
        para('must be displayed'),
        blank_line,
        blank_line)

    assert_equal expected, out
  end

  def test_add_method_documentation
    util_store

    out = doc()

    missing = RDoc::AnyMethod.new nil, 'missing'
    @cFoo.add_method missing

    @driver.add_method_documentation out, @cFoo

    expected =
      doc(
        head(1, 'Foo#inherit'),
        blank_line,
        para("(from #{@rdoc_home})"),
        rule(1),
        blank_line,
        blank_line,
        head(1, 'Foo#override'),
        blank_line,
        para("(from #{@rdoc_home})"),
        rule(1),
        blank_line,
        para('must not be displayed in Bar#override'),
        blank_line,
        blank_line)

    assert_equal expected, out
  end

  def test_add_method_list
    out = @RM::Document.new

    @driver.add_method_list out, %w[new parse], 'Class methods'

    expected = @RM::Document.new(
      @RM::Heading.new(1, 'Class methods:'),
      @RM::BlankLine.new,
      @RM::Verbatim.new('new'),
      @RM::Verbatim.new('parse'),
      @RM::BlankLine.new)

    assert_equal expected, out
  end

  def test_output_width
    @options[:width] = 10
    driver = RDoc::RI::Driver.new @options

    doc = @RM::Document.new
    doc << @RM::IndentedParagraph.new(0, 'new, parse, foo, bar, baz')

    out, = capture_output do
      driver.display doc
    end

    expected = "new, parse, foo,\nbar, baz\n"

    assert_equal expected, out
  end

  def test_add_method_list_interative
    @options[:interactive] = true
    driver = RDoc::RI::Driver.new @options

    out = @RM::Document.new

    driver.add_method_list out, %w[new parse], 'Class methods'

    expected = @RM::Document.new(
      @RM::Heading.new(1, 'Class methods:'),
      @RM::BlankLine.new,
      @RM::IndentedParagraph.new(2, 'new, parse'),
      @RM::BlankLine.new)

    assert_equal expected, out
  end

  def test_add_method_list_none
    out = @RM::Document.new

    @driver.add_method_list out, [], 'Class'

    assert_equal @RM::Document.new, out
  end

  def test_ancestors_of
    util_ancestors_store

    assert_equal %w[X Mixin Object Foo], @driver.ancestors_of('Foo::Bar')
  end

  def test_classes
    util_multi_store

    expected = {
      'Ambiguous' => [@store1, @store2],
      'Bar'       => [@store2],
      'Ext'       => [@store1],
      'Foo'       => [@store1, @store2],
      'Foo::Bar'  => [@store1],
      'Foo::Baz'  => [@store1, @store2],
      'Inc'       => [@store1],
      'Qux'       => [@store1],
    }

    classes = @driver.classes

    assert_equal expected.keys.sort, classes.keys.sort

    expected.each do |klass, stores|
      assert_equal stores, classes[klass].sort_by { |store| store.path },
                   "mismatch for #{klass}"
    end
  end

  def test_class_document
    util_store

    tl1 = @store1.add_file 'one.rb'
    tl2 = @store1.add_file 'two.rb'

    @cFoo.add_comment 'one', tl1
    @cFoo.add_comment 'two', tl2

    @store1.save_class @cFoo

    found = [
      [@store1, @store1.load_class(@cFoo.full_name)]
    ]

    extends  = [[[@cFooExt], @store1]]
    includes = [[[@cFooInc], @store1]]

    out = @driver.class_document @cFoo.full_name, found, [], includes, extends

    expected = @RM::Document.new
    @driver.add_class expected, 'Foo', []
    @driver.add_includes expected, includes
    @driver.add_extends  expected, extends
    @driver.add_from expected, @store1
    expected << @RM::Rule.new(1)

    doc = @RM::Document.new(@RM::Paragraph.new('one'))
    doc.file = 'one.rb'
    expected.push doc
    expected << @RM::BlankLine.new
    doc = @RM::Document.new(@RM::Paragraph.new('two'))
    doc.file = 'two.rb'
    expected.push doc

    expected << @RM::Rule.new(1)
    expected << @RM::Heading.new(1, 'Instance methods:')
    expected << @RM::BlankLine.new
    expected << @RM::Verbatim.new('inherit')
    expected << @RM::Verbatim.new('override')
    expected << @RM::BlankLine.new

    assert_equal expected, out
  end

  def test_complete
    store = RDoc::RI::Store.new @home_ri
    store.cache[:ancestors] = {
      'Foo'      => %w[Object],
      'Foo::Bar' => %w[Object],
    }
    store.cache[:class_methods] = {
      'Foo' => %w[bar]
    }
    store.cache[:instance_methods] = {
      'Foo' => %w[Bar]
    }
    store.cache[:modules] = %w[
      Foo
      Foo::Bar
    ]

    @driver.stores = [store]

    assert_equal %w[Foo         ], @driver.complete('F')
    assert_equal %w[    Foo::Bar], @driver.complete('Foo::B')

    assert_equal %w[Foo#Bar],           @driver.complete('Foo#'),   'Foo#'
    assert_equal %w[Foo#Bar  Foo::bar], @driver.complete('Foo.'),   'Foo.'
    assert_equal %w[Foo::Bar Foo::bar], @driver.complete('Foo::'),  'Foo::'

    assert_equal %w[         Foo::bar], @driver.complete('Foo::b'), 'Foo::b'
  end

  def test_complete_ancestor
    util_ancestors_store

    assert_equal %w[Foo::Bar#i_method], @driver.complete('Foo::Bar#')

    assert_equal %w[Foo::Bar#i_method Foo::Bar::c_method Foo::Bar::new],
                 @driver.complete('Foo::Bar.')
  end

  def test_complete_classes
    util_store

    assert_equal %w[                       ], @driver.complete('[')
    assert_equal %w[                       ], @driver.complete('[::')
    assert_equal %w[Foo                    ], @driver.complete('F')
    assert_equal %w[Foo:: Foo::Bar Foo::Baz], @driver.complete('Foo::')
    assert_equal %w[      Foo::Bar Foo::Baz], @driver.complete('Foo::B')
  end

  def test_complete_multistore
    util_multi_store

    assert_equal %w[Bar], @driver.complete('B')
    assert_equal %w[Foo], @driver.complete('F')
    assert_equal %w[Foo::Bar Foo::Baz], @driver.complete('Foo::B')
  end

  def test_display
    doc = @RM::Document.new(
            @RM::Paragraph.new('hi'))

    out, = capture_output do
      @driver.display doc
    end

    assert_equal "hi\n", out
  end

  def test_display_class
    util_store

    out, = capture_output do
      @driver.display_class 'Foo::Bar'
    end

    assert_match %r%^= Foo::Bar%, out
    assert_match %r%^\(from%, out

    assert_match %r%^= Class methods:%, out
    assert_match %r%^  new%, out
    assert_match %r%^= Instance methods:%, out
    assert_match %r%^  blah%, out
    assert_match %r%^= Attributes:%, out
    assert_match %r%^  attr_accessor attr%, out

    assert_equal 1, out.scan(/-\n/).length

    refute_match %r%Foo::Bar#blah%, out
  end

  def test_display_class_all
    util_store

    @driver.show_all = true

    out, = capture_output do
      @driver.display_class 'Foo::Bar'
    end

    assert_match %r%^= Foo::Bar%, out
    assert_match %r%^\(from%, out

    assert_match %r%^= Class methods:%, out
    assert_match %r%^  new%, out
    assert_match %r%^= Instance methods:%, out
    assert_match %r%^  blah%, out
    assert_match %r%^= Attributes:%, out
    assert_match %r%^  attr_accessor attr%, out

    assert_equal 6, out.scan(/-\n/).length

    assert_match %r%Foo::Bar#blah%, out
  end

  def test_display_class_ambiguous
    util_multi_store

    out, = capture_output do
      @driver.display_class 'Ambiguous'
    end

    assert_match %r%^= Ambiguous < Object$%, out
  end

  def test_display_class_multi_no_doc
    util_multi_store

    out, = capture_output do
      @driver.display_class 'Foo::Baz'
    end

    assert_match %r%^= Foo::Baz%, out
    assert_match %r%-\n%, out
    assert_match %r%Also found in:%, out
    assert_match %r%#{Regexp.escape @home_ri}%, out
    assert_match %r%#{Regexp.escape @home_ri2}%, out
  end

  def test_display_class_superclass
    util_multi_store

    out, = capture_output do
      @driver.display_class 'Bar'
    end

    assert_match %r%^= Bar < Foo%, out
  end

  def test_display_class_module
    util_store

    out, = capture_output do
      @driver.display_class 'Inc'
    end

    assert_match %r%^= Inc$%, out
  end

  def test_display_class_page
    out, = capture_output do
      @driver.display_class 'ruby:README'
    end

    assert_empty out
  end

  def test_display_method
    util_store

    out, = capture_output do
      @driver.display_method 'Foo::Bar#blah'
    end

    assert_match %r%Foo::Bar#blah%, out
    assert_match %r%blah.5%,        out
    assert_match %r%blah.6%,        out
  end

  def test_display_method_attribute
    util_store

    out, = capture_output do
      @driver.display_method 'Foo::Bar#attr'
    end

    assert_match %r%Foo::Bar#attr%, out
    refute_match %r%Implementation from%, out
  end

  def test_display_method_inherited
    util_multi_store

    out, = capture_output do
      @driver.display_method 'Bar#inherit'
    end

    assert_match %r%^= Bar#inherit%, out
    assert_match %r%^=== Implementation from Foo%, out
  end

  def test_display_method_overridden
    util_multi_store

    out, = capture_output do
      @driver.display_method 'Bar#override'
    end

    refute_match %r%must not be displayed%, out
  end

  def test_display_name
    util_store

    out, = capture_output do
      assert_equal true, @driver.display_name('home:README.rdoc')
    end

    expected = <<-EXPECTED
= README
This is a README
    EXPECTED

    assert_equal expected, out
  end

  def test_display_name_not_found_class
    util_store

    out, = capture_output do
      assert_equal false, @driver.display_name('Foo::B')
    end

    expected = <<-EXPECTED
Foo::B not found, maybe you meant:

Foo::Bar
Foo::Baz
    EXPECTED

    assert_equal expected, out
  end

  def test_display_name_not_found_method
    util_store

    out, = capture_output do
      assert_equal false, @driver.display_name('Foo::Bar#b')
    end

    expected = <<-EXPECTED
Foo::Bar#b not found, maybe you meant:

Foo::Bar#blah
Foo::Bar#bother
    EXPECTED

    assert_equal expected, out
  end

  def test_display_name_not_found_special
    util_store

    assert_raise RDoc::RI::Driver::NotFoundError do
      assert_equal false, @driver.display_name('Set#[]')
    end
  end

  def test_display_method_params
    util_store

    out, = capture_output do
      @driver.display_method 'Foo::Bar#bother'
    end

    assert_match %r%things.*stuff%, out
  end

  def test_display_page
    util_store

    out, = capture_output do
      @driver.display_page 'home:README.rdoc'
    end

    assert_match %r%= README%, out
  end

  def test_display_page_add_extension
    util_store

    out, = capture_output do
      @driver.display_page 'home:README'
    end

    assert_match %r%= README%, out
  end

  def test_display_page_ambiguous
    util_store

    other = @store1.add_file 'README.md'
    other.parser = RDoc::Parser::Simple
    other.comment =
      doc(
        head(1, 'README.md'),
        para('This is the other README'))

    @store1.save_page other

    out, = capture_output do
      @driver.display_page 'home:README'
    end

    assert_match %r%= README pages in #{@rdoc_home}%, out
    assert_match %r%README\.rdoc%,               out
    assert_match %r%README\.md%,                 out
  end

  def test_display_page_extension
    util_store

    other = @store1.add_file 'README.EXT'
    other.parser = RDoc::Parser::Simple
    other.comment =
      doc(
        head(1, 'README.EXT'),
        para('This is the other README'))

    @store1.save_page other

    out, = capture_output do
      @driver.display_page 'home:README.EXT'
    end

    assert_match 'other README', out
  end

  def test_display_page_ignore_directory
    util_store

    other = @store1.add_file 'doc/globals.rdoc'
    other.parser = RDoc::Parser::Simple
    other.comment =
      doc(
        head(1, 'globals.rdoc'),
        para('Globals go here'))

    @store1.save_page other

    out, = capture_output do
      @driver.display_page 'home:globals'
    end

    assert_match %r%= globals\.rdoc%, out
  end

  def test_display_page_missing
    util_store

    out, = capture_output do
      @driver.display_page 'home:missing'
    end

    out, = capture_output do
      @driver.display_page_list @store1
    end

    assert_match %r%= Pages in #{@rdoc_home}%, out
    assert_match %r%README\.rdoc%,        out
  end

  def test_display_page_list
    util_store

    other = @store1.add_file 'OTHER.rdoc'
    other.parser = RDoc::Parser::Simple
    other.comment =
      doc(
        head(1, 'OTHER'),
        para('This is OTHER'))

    @store1.save_page other

    out, = capture_output do
      @driver.display_page_list @store1
    end

    assert_match %r%= Pages in #{@rdoc_home}%, out
    assert_match %r%README\.rdoc%,        out
    assert_match %r%OTHER\.rdoc%,         out
  end

  def test_expand_class
    util_store

    assert_equal 'Foo',       @driver.expand_class('F')
    assert_equal 'Foo::Bar',  @driver.expand_class('F::Bar')

    assert_raise RDoc::RI::Driver::NotFoundError do
      @driver.expand_class 'F::B'
    end
  end

  def test_expand_class_2
    @store1 = RDoc::RI::Store.new @home_ri, :home

    @top_level = @store1.add_file 'file.rb'

    @cFoo = @top_level.add_class RDoc::NormalClass, 'Foo'
    @mFox = @top_level.add_module RDoc::NormalModule, 'Fox'
    @cFoo_Bar = @cFoo.add_class RDoc::NormalClass, 'Bar'
    @store1.save

    @driver.stores = [@store1]
    assert_raise RDoc::RI::Driver::NotFoundError do
      @driver.expand_class 'F'
    end
    assert_equal 'Foo::Bar',  @driver.expand_class('F::Bar')
    assert_equal 'Foo::Bar',  @driver.expand_class('F::B')
  end

  def test_expand_class_3
    @store1 = RDoc::RI::Store.new @home_ri, :home

    @top_level = @store1.add_file 'file.rb'

    @cFoo = @top_level.add_class RDoc::NormalClass, 'Foo'
    @mFox = @top_level.add_module RDoc::NormalModule, 'FooBar'
    @store1.save

    @driver.stores = [@store1]

    assert_equal 'Foo',  @driver.expand_class('Foo')
  end

  def test_expand_name
    util_store

    assert_equal '.b',        @driver.expand_name('b')
    assert_equal 'Foo',       @driver.expand_name('F')
    assert_equal 'Foo::Bar#', @driver.expand_name('F::Bar#')

    e = assert_raise RDoc::RI::Driver::NotFoundError do
      @driver.expand_name 'Z'
    end

    assert_equal 'Z', e.name

    @driver.stores << RDoc::Store.new(nil, :system)

    assert_equal 'ruby:README', @driver.expand_name('ruby:README')
    assert_equal 'ruby:',       @driver.expand_name('ruby:')

    e = assert_raise RDoc::RI::Driver::NotFoundError do
      @driver.expand_name 'nonexistent_gem:'
    end

    assert_equal 'nonexistent_gem', e.name
  end

  def test_find_methods
    util_store

    items = []

    @driver.find_methods 'Foo::Bar.' do |store, klass, ancestor, types, method|
      items << [store, klass, ancestor, types, method]
    end

    expected = [
      [@store1, 'Foo::Bar', 'Foo::Bar', :both, nil],
    ]

    assert_equal expected, items
  end

  def test_find_methods_method
    util_store

    items = []

    @driver.find_methods '.blah' do |store, klass, ancestor, types, method|
      items << [store, klass, ancestor, types, method]
    end

    expected = [
      [@store1, 'Ambiguous', 'Ambiguous', :both, 'blah'],
      [@store1, 'Ext',       'Ext',       :both, 'blah'],
      [@store1, 'Foo',       'Foo',       :both, 'blah'],
      [@store1, 'Foo::Bar',  'Foo::Bar',  :both, 'blah'],
      [@store1, 'Foo::Baz',  'Foo::Baz',  :both, 'blah'],
      [@store1, 'Inc',       'Inc',       :both, 'blah'],
      [@store1, 'Qux',       'Qux',       :both, 'blah'],
    ]

    assert_equal expected, items
  end

  def test_filter_methods
    util_multi_store

    name = 'Bar#override'

    found = @driver.load_methods_matching name

    sorted = @driver.filter_methods found, name

    expected = [[@store2, [@override]]]

    assert_equal expected, sorted
  end

  def test_filter_methods_not_found
    util_multi_store

    name = 'Bar#inherit'

    found = @driver.load_methods_matching name

    sorted = @driver.filter_methods found, name

    assert_equal found, sorted
  end

  def test_find_store
    @driver.stores << RDoc::Store.new(nil,              :system)
    @driver.stores << RDoc::Store.new('doc/gem-1.0/ri', :gem)

    assert_equal 'ruby',    @driver.find_store('ruby')
    assert_equal 'gem-1.0', @driver.find_store('gem-1.0')
    assert_equal 'gem-1.0', @driver.find_store('gem')

    e = assert_raise RDoc::RI::Driver::NotFoundError do
      @driver.find_store 'nonexistent'
    end

    assert_equal 'nonexistent', e.name
  end

  def test_did_you_mean
    omit 'skip test with did_you_men' unless defined? DidYouMean::SpellChecker

    util_ancestors_store

    e = assert_raise RDoc::RI::Driver::NotFoundError do
      @driver.lookup_method 'Foo.i_methdo'
    end
    assert_equal "Nothing known about Foo.i_methdo\nDid you mean?  i_method", e.message

    e = assert_raise RDoc::RI::Driver::NotFoundError do
      @driver.lookup_method 'Foo#i_methdo'
    end
    assert_equal "Nothing known about Foo#i_methdo\nDid you mean?  i_method", e.message

    e = assert_raise RDoc::RI::Driver::NotFoundError do
      @driver.lookup_method 'Foo::i_methdo'
    end
    assert_equal "Nothing known about Foo::i_methdo\nDid you mean?  c_method", e.message
  end

  def test_formatter
    tty = Object.new
    def tty.tty?() true; end

    @options.delete :use_stdout
    @options.delete :formatter

    driver = RDoc::RI::Driver.new @options

    assert_instance_of @RM::ToAnsi, driver.formatter(tty)

    assert_instance_of @RM::ToBs, driver.formatter(StringIO.new)

    driver.instance_variable_set :@paging, true

    assert_instance_of @RM::ToBs, driver.formatter(StringIO.new)
  end

  def test_in_path_eh
    path = ENV['PATH']

    test_path = File.expand_path '..', __FILE__

    temp_dir do |dir|
      nonexistent = File.join dir, 'nonexistent'
      refute @driver.in_path?(nonexistent)

      ENV['PATH'] = test_path

      assert @driver.in_path?(File.basename(__FILE__))
    end
  ensure
    ENV['PATH'] = path
  end

  def test_method_type
    assert_equal :both,     @driver.method_type(nil)
    assert_equal :both,     @driver.method_type('.')
    assert_equal :instance, @driver.method_type('#')
    assert_equal :class,    @driver.method_type('::')
  end

  def test_name_regexp
    assert_equal %r%^RDoc::AnyMethod#new$%,
                 @driver.name_regexp('RDoc::AnyMethod#new')

    assert_equal %r%^RDoc::AnyMethod::new$%,
                 @driver.name_regexp('RDoc::AnyMethod::new')

    assert_equal %r%^RDoc::AnyMethod(#|::)new$%,
                 @driver.name_regexp('RDoc::AnyMethod.new')

    assert_equal %r%^Hash(#|::)\[\]$%,
                 @driver.name_regexp('Hash.[]')

    assert_equal %r%^Hash::\[\]$%,
                 @driver.name_regexp('Hash::[]')
  end

  def test_list_known_classes
    util_store

    out, = capture_output do
      @driver.list_known_classes
    end

    assert_equal "Ambiguous\nExt\nFoo\nFoo::Bar\nFoo::Baz\nInc\nQux\n", out
  end

  def test_list_known_classes_name
    util_store

    out, = capture_output do
      @driver.list_known_classes %w[F I]
    end

    assert_equal "Foo\nFoo::Bar\nFoo::Baz\nInc\n", out
  end

  def test_list_methods_matching
    util_store

    assert_equal %w[
        Foo::Bar#attr
        Foo::Bar#blah
        Foo::Bar#bother
        Foo::Bar::new
      ],
      @driver.list_methods_matching('Foo::Bar.').sort
  end

  def test_list_methods_matching_inherit
    util_multi_store

    assert_equal %w[
        Bar#baz
        Bar#inherit
        Bar#override
      ],
      @driver.list_methods_matching('Bar.').sort
  end

  def test_list_methods_matching_regexp
    util_store

    index = RDoc::AnyMethod.new nil, '[]'
    index.record_location @top_level
    @cFoo.add_method index
    @store1.save_method @cFoo, index

    c_index = RDoc::AnyMethod.new nil, '[]'
    c_index.singleton = true
    c_index.record_location @top_level
    @cFoo.add_method c_index
    @store1.save_method @cFoo, c_index

    @store1.save_cache

    assert_equal %w[Foo#[]], @driver.list_methods_matching('Foo#[]')
    assert_equal %w[Foo::[]], @driver.list_methods_matching('Foo::[]')
  end

  def test_load_method
    util_store

    method = @driver.load_method(@store1, :instance_methods, 'Foo', '#',
                                 'inherit')

    assert_equal @inherit, method
  end

  def test_load_method_inherited
    util_multi_store

    method = @driver.load_method(@store2, :instance_methods, 'Bar', '#',
                                 'inherit')

    assert_nil method
  end

  def test_load_methods_matching
    util_store

    expected = [[@store1, [@inherit]]]

    assert_equal expected, @driver.load_methods_matching('Foo#inherit')

    expected = [[@store1, [@blah]]]

    assert_equal expected, @driver.load_methods_matching('.blah')

    assert_empty @driver.load_methods_matching('.b')
  end

  def test_load_methods_matching_inherited
    util_multi_store

    expected = [[@store1, [@inherit]]]

    assert_equal expected, @driver.load_methods_matching('Bar#inherit')
  end

  def test_load_method_missing
    util_store

    FileUtils.rm @store1.method_file 'Foo', '#inherit'

    method = @driver.load_method(@store1, :instance_methods, 'Foo', '#',
                                 'inherit')

    assert_equal '(unknown)#inherit', method.full_name
  end

  def _test_page # this test doesn't do anything anymore :(
    @driver.use_stdout = false

    with_dummy_pager do
      @driver.page do |io|
        omit "couldn't find a standard pager" if io == $stdout

        assert @driver.paging?
      end
    end

    refute @driver.paging?
  end

  # this test is too fragile. Perhaps using Process.spawn will make this
  # reliable
  def _test_page_in_presence_of_child_status
    @driver.use_stdout = false

    with_dummy_pager do
      @driver.page do |io|
        refute_equal $stdout, io
        assert @driver.paging?
      end
    end
  end

  def test_page_stdout
    @driver.use_stdout = true

    @driver.page do |io|
      assert_equal $stdout, io
    end

    refute @driver.paging?
  end

  def test_parse_name_method
    klass, type, meth = @driver.parse_name 'foo'

    assert_equal '',    klass, 'foo class'
    assert_equal '.',   type,  'foo type'
    assert_equal 'foo', meth,  'foo method'

    klass, type, meth = @driver.parse_name '#foo'

    assert_equal '',    klass, '#foo class'
    assert_equal '#',   type,  '#foo type'
    assert_equal 'foo', meth,  '#foo method'

    klass, type, meth = @driver.parse_name '::foo'

    assert_equal '',    klass, '::foo class'
    assert_equal '::',  type,  '::foo type'
    assert_equal 'foo', meth,  '::foo method'
  end

  def test_parse_name_page
    klass, type, meth = @driver.parse_name 'ruby:README'

    assert_equal 'ruby',   klass, 'ruby project'
    assert_equal ':',      type,  'ruby type'
    assert_equal 'README', meth,  'ruby page'

    klass, type, meth = @driver.parse_name 'ruby:'

    assert_equal 'ruby',   klass, 'ruby project'
    assert_equal ':',      type,  'ruby type'
    assert_nil             meth,  'ruby page'
  end

  def test_parse_name_page_extenson
    klass, type, meth = @driver.parse_name 'ruby:README.EXT'

    assert_equal 'ruby',      klass, 'ruby project'
    assert_equal ':',         type,  'ruby type'
    assert_equal 'README.EXT', meth,  'ruby page'
  end

  def test_parse_name_single_class
    klass, type, meth = @driver.parse_name 'Foo'

    assert_equal 'Foo', klass, 'Foo class'
    assert_nil          type,  'Foo type'
    assert_nil          meth,  'Foo method'

    klass, type, meth = @driver.parse_name 'Foo#'

    assert_equal 'Foo', klass, 'Foo# class'
    assert_equal '#',   type,  'Foo# type'
    assert_nil          meth,  'Foo# method'

    klass, type, meth = @driver.parse_name 'Foo::'

    assert_equal 'Foo', klass, 'Foo:: class'
    assert_equal '::',  type,  'Foo:: type'
    assert_nil          meth,  'Foo:: method'

    klass, type, meth = @driver.parse_name 'Foo.'

    assert_equal 'Foo', klass, 'Foo. class'
    assert_equal '.',   type,  'Foo. type'
    assert_nil          meth,  'Foo. method'

    klass, type, meth = @driver.parse_name 'Foo#Bar'

    assert_equal 'Foo', klass, 'Foo#Bar class'
    assert_equal '#',   type,  'Foo#Bar type'
    assert_equal 'Bar', meth,  'Foo#Bar method'

    klass, type, meth = @driver.parse_name 'Foo.Bar'

    assert_equal 'Foo', klass, 'Foo.Bar class'
    assert_equal '.',   type,  'Foo.Bar type'
    assert_equal 'Bar', meth,  'Foo.Bar method'

    klass, type, meth = @driver.parse_name 'Foo::bar'

    assert_equal 'Foo', klass, 'Foo::bar class'
    assert_equal '::',  type,  'Foo::bar type'
    assert_equal 'bar', meth,  'Foo::bar method'
  end

  def test_parse_name_namespace
    klass, type, meth = @driver.parse_name 'Foo::Bar'

    assert_equal 'Foo::Bar', klass, 'Foo::Bar class'
    assert_nil               type,  'Foo::Bar type'
    assert_nil               meth,  'Foo::Bar method'

    klass, type, meth = @driver.parse_name 'Foo::Bar#'

    assert_equal 'Foo::Bar', klass, 'Foo::Bar# class'
    assert_equal '#',        type,  'Foo::Bar# type'
    assert_nil               meth,  'Foo::Bar# method'

    klass, type, meth = @driver.parse_name 'Foo::Bar#baz'

    assert_equal 'Foo::Bar', klass, 'Foo::Bar#baz class'
    assert_equal '#',        type,  'Foo::Bar#baz type'
    assert_equal 'baz',      meth,  'Foo::Bar#baz method'
  end

  def test_parse_name_special
    specials = %w[
      %
      &
      *
      +
      +@
      -
      -@
      /
      <
      <<
      <=
      <=>
      ==
      ===
      =>
      =~
      >
      >>
      []
      []=
      ^
      `
      |
      ~
      ~@
    ]

    specials.each do |special|
      parsed = @driver.parse_name special

      assert_equal ['', '.', special], parsed
    end
  end

  def _test_setup_pager # this test doesn't do anything anymore :(
    @driver.use_stdout = false

    pager = with_dummy_pager do @driver.setup_pager end

    omit "couldn't find a standard pager" unless pager

    assert @driver.paging?
  ensure
    pager.close if pager
  end

  def util_ancestors_store
    store1 = RDoc::RI::Store.new @home_ri
    store1.cache[:ancestors] = {
      'Foo'      => %w[Object],
      'Foo::Bar' => %w[Foo],
    }
    store1.cache[:class_methods] = {
      'Foo'      => %w[c_method new],
      'Foo::Bar' => %w[new],
    }
    store1.cache[:instance_methods] = {
      'Foo' => %w[i_method],
    }
    store1.cache[:modules] = %w[
      Foo
      Foo::Bar
    ]

    store2 = RDoc::RI::Store.new @home_ri
    store2.cache[:ancestors] = {
      'Foo'    => %w[Mixin Object],
      'Mixin'  => %w[],
      'Object' => %w[X Object],
      'X'      => %w[Object],
    }
    store2.cache[:class_methods] = {
      'Foo'    => %w[c_method new],
      'Mixin'  => %w[],
      'X'      => %w[],
      'Object' => %w[],
    }
    store2.cache[:instance_methods] = {
      'Foo'   => %w[i_method],
      'Mixin' => %w[],
    }
    store2.cache[:modules] = %w[
      Foo
      Mixin
      Object
      X
    ]

    @driver.stores = store1, store2
  end

  def util_multi_store
    util_store

    @home_ri2 = "#{@home_ri}2"
    @store2 = RDoc::RI::Store.new @home_ri2

    @top_level = @store2.add_file 'file.rb'

    # as if seen in a namespace like class Ambiguous::Other
    @mAmbiguous = @top_level.add_module RDoc::NormalModule, 'Ambiguous'

    @cFoo = @top_level.add_class RDoc::NormalClass, 'Foo'

    @cBar = @top_level.add_class RDoc::NormalClass, 'Bar', 'Foo'
    @cFoo_Baz = @cFoo.add_class RDoc::NormalClass, 'Baz'

    @baz = @cBar.add_method RDoc::AnyMethod.new(nil, 'baz')
    @baz.record_location @top_level

    @override = @cBar.add_method RDoc::AnyMethod.new(nil, 'override')
    @override.comment = 'must be displayed'
    @override.record_location @top_level

    @store2.save

    @driver.stores = [@store1, @store2]
  end

  def util_store
    @store1 = RDoc::RI::Store.new @home_ri, :home

    @top_level = @store1.add_file 'file.rb'

    @readme = @store1.add_file 'README.rdoc'
    @readme.parser = RDoc::Parser::Simple
    @readme.comment =
      doc(
        head(1, 'README'),
        para('This is a README'))

    @cFoo = @top_level.add_class RDoc::NormalClass, 'Foo'
    @mExt = @top_level.add_module RDoc::NormalModule, 'Ext'
    @mInc = @top_level.add_module RDoc::NormalModule, 'Inc'
    @cAmbiguous = @top_level.add_class RDoc::NormalClass, 'Ambiguous'

    doc = @RM::Document.new @RM::Paragraph.new('Extend thingy')
    @cFooExt = @cFoo.add_extend RDoc::Extend.new('Ext', doc)
    @cFooExt.record_location @top_level
    doc = @RM::Document.new @RM::Paragraph.new('Include thingy')
    @cFooInc = @cFoo.add_include RDoc::Include.new('Inc', doc)
    @cFooInc.record_location @top_level

    @cFoo_Bar = @cFoo.add_class RDoc::NormalClass, 'Bar'

    @blah = @cFoo_Bar.add_method RDoc::AnyMethod.new(nil, 'blah')
    @blah.call_seq = "blah(5) => 5\nblah(6) => 6\n"
    @blah.record_location @top_level

    @bother = @cFoo_Bar.add_method RDoc::AnyMethod.new(nil, 'bother')
    @bother.block_params = "stuff"
    @bother.params = "(things)"
    @bother.record_location @top_level

    @new = @cFoo_Bar.add_method RDoc::AnyMethod.new nil, 'new'
    @new.record_location @top_level
    @new.singleton = true

    @attr = @cFoo_Bar.add_attribute RDoc::Attr.new nil, 'attr', 'RW', ''
    @attr.record_location @top_level

    @cFoo_Baz = @cFoo.add_class RDoc::NormalClass, 'Baz'
    @cFoo_Baz.record_location @top_level

    @inherit = @cFoo.add_method RDoc::AnyMethod.new(nil, 'inherit')
    @inherit.record_location @top_level

    # overridden by Bar in multi_store
    @overridden = @cFoo.add_method RDoc::AnyMethod.new(nil, 'override')
    @overridden.comment = 'must not be displayed in Bar#override'
    @overridden.record_location @top_level

    @cQux = @top_level.add_class RDoc::NormalClass, 'Qux'

    @original = @cQux.add_method RDoc::AnyMethod.new(nil, 'original')
    @original.comment = 'original comment'
    @original.record_location @top_level

    @aliased = @original.add_alias RDoc::Alias.new(nil, 'original', 'aliased', 'alias comment'), @cQux
    @aliased.record_location @top_level

    @store1.save

    @driver.stores = [@store1]
  end

end
