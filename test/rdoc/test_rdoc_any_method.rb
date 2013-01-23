require File.expand_path '../xref_test_case', __FILE__

class TestRDocAnyMethod < XrefTestCase

  def test_aref
    m = RDoc::AnyMethod.new nil, 'method?'

    assert_equal 'method-i-method-3F', m.aref

    m.singleton = true

    assert_equal 'method-c-method-3F', m.aref
  end

  def test_arglists
    m = RDoc::AnyMethod.new nil, 'method'

    assert_nil m.arglists

    m.params = "(a, b)"
    m.block_params = "c, d"

    assert_equal "method(a, b) { |c, d| ... }", m.arglists

    call_seq = <<-SEQ
method(a) { |c| ... }
method(a, b) { |c, d| ... }
    SEQ

    m.call_seq = call_seq.dup

    assert_equal call_seq, m.arglists
  end

  def test_c_function
    @c1_m.c_function = 'my_c1_m'

    assert_equal 'my_c1_m', @c1_m.c_function
  end

  def test_full_name
    assert_equal 'C1::m', @c1.method_list.first.full_name
  end

  def test_markup_code
    tokens = [
      RDoc::RubyToken::TkCONSTANT. new(0, 0, 0, 'CONSTANT'),
    ]

    @c2_a.collect_tokens
    @c2_a.add_tokens(*tokens)

    expected = '<span class="ruby-constant">CONSTANT</span>'

    assert_equal expected, @c2_a.markup_code
  end

  def test_markup_code_empty
    assert_equal '', @c2_a.markup_code
  end

  def test_marshal_dump
    @store.path = Dir.tmpdir
    top_level = @store.add_file 'file.rb'

    m = RDoc::AnyMethod.new nil, 'method'
    m.block_params = 'some_block'
    m.call_seq     = 'call_seq'
    m.comment      = 'this is a comment'
    m.params       = 'param'
    m.record_location top_level

    cm = top_level.add_class RDoc::ClassModule, 'Klass'
    cm.add_method m

    section = cm.sections.first

    al = RDoc::Alias.new nil, 'method', 'aliased', 'alias comment'
    al_m = m.add_alias al, cm

    loaded = Marshal.load Marshal.dump m
    loaded.store = @store

    comment = RDoc::Markup::Document.new(
                RDoc::Markup::Paragraph.new('this is a comment'))

    assert_equal m, loaded

    assert_equal [al_m.name],    loaded.aliases.map { |alas| alas.name }
    assert_equal 'some_block',   loaded.block_params
    assert_equal 'call_seq',     loaded.call_seq
    assert_equal comment,        loaded.comment
    assert_equal top_level,      loaded.file
    assert_equal 'Klass#method', loaded.full_name
    assert_equal 'method',       loaded.name
    assert_equal 'param',        loaded.params
    assert_equal nil,            loaded.singleton # defaults to nil
    assert_equal :public,        loaded.visibility
    assert_equal cm,             loaded.parent
    assert_equal section,        loaded.section
  end

  def test_marshal_load_aliased_method
    aliased_method = Marshal.load Marshal.dump(@c2.method_list.last)

    assert_equal 'C2#a',  aliased_method.full_name
    assert_equal 'C2',    aliased_method.parent_name
    assert_equal '()',    aliased_method.params
    assert                aliased_method.display?
  end

  def test_marshal_load_class_method
    class_method = Marshal.load Marshal.dump(@c1.method_list.first)

    assert_equal 'C1::m', class_method.full_name
    assert_equal 'C1',    class_method.parent_name
    assert_equal '()',    class_method.params
    assert                class_method.display?
  end

  def test_marshal_load_instance_method
    instance_method = Marshal.load Marshal.dump(@c1.method_list.last)

    assert_equal 'C1#m',  instance_method.full_name
    assert_equal 'C1',    instance_method.parent_name
    assert_equal '(foo)', instance_method.params
    assert                instance_method.display?
  end

  def test_marshal_load_version_0
    @store.path = Dir.tmpdir
    top_level = @store.add_file 'file.rb'

    m = RDoc::AnyMethod.new nil, 'method'

    cm = top_level.add_class RDoc::ClassModule, 'Klass'
    cm.add_method m

    section = cm.sections.first

    al = RDoc::Alias.new nil, 'method', 'aliased', 'alias comment'
    al_m = m.add_alias al, cm

    loaded = Marshal.load "\x04\bU:\x14RDoc::AnyMethod[\x0Fi\x00I" +
                          "\"\vmethod\x06:\x06EF\"\x11Klass#method0:\vpublic" +
                          "o:\eRDoc::Markup::Document\x06:\v@parts[\x06" +
                          "o:\x1CRDoc::Markup::Paragraph\x06;\t[\x06I" +
                          "\"\x16this is a comment\x06;\x06FI" +
                          "\"\rcall_seq\x06;\x06FI\"\x0Fsome_block\x06;\x06F" +
                          "[\x06[\aI\"\faliased\x06;\x06Fo;\b\x06;\t[\x06" +
                          "o;\n\x06;\t[\x06I\"\x12alias comment\x06;\x06FI" +
                          "\"\nparam\x06;\x06F"

    loaded.store = @store

    comment = RDoc::Markup::Document.new(
                RDoc::Markup::Paragraph.new('this is a comment'))

    assert_equal m, loaded

    assert_equal [al_m.name],    loaded.aliases.map { |alas| alas.name }
    assert_equal 'some_block',   loaded.block_params
    assert_equal 'call_seq',     loaded.call_seq
    assert_equal comment,        loaded.comment
    assert_equal 'Klass#method', loaded.full_name
    assert_equal 'method',       loaded.name
    assert_equal 'param',        loaded.params
    assert_equal nil,            loaded.singleton # defaults to nil
    assert_equal :public,        loaded.visibility
    assert_equal nil,            loaded.file
    assert_equal cm,             loaded.parent
    assert_equal section,        loaded.section

    assert loaded.display?
  end

  def test_name
    m = RDoc::AnyMethod.new nil, nil

    assert_nil m.name
  end

  def test_param_list_block_params
    m = RDoc::AnyMethod.new nil, 'method'
    m.parent = @c1

    m.block_params = 'c, d'

    assert_equal %w[c d], m.param_list
  end

  def test_param_list_call_seq
    m = RDoc::AnyMethod.new nil, 'method'
    m.parent = @c1

    call_seq = <<-SEQ
method(a) { |c| ... }
method(a, b) { |c, d| ... }
    SEQ

    m.call_seq = call_seq

    assert_equal %w[a b c d], m.param_list
  end

  def test_param_list_default
    m = RDoc::AnyMethod.new nil, 'method'
    m.parent = @c1

    m.params = '(b = default)'

    assert_equal %w[b], m.param_list
  end

  def test_param_list_params
    m = RDoc::AnyMethod.new nil, 'method'
    m.parent = @c1

    m.params = '(a, b)'

    assert_equal %w[a b], m.param_list
  end

  def test_param_list_params_block_params
    m = RDoc::AnyMethod.new nil, 'method'
    m.parent = @c1

    m.params = '(a, b)'
    m.block_params = 'c, d'

    assert_equal %w[a b c d], m.param_list
  end

  def test_param_seq
    m = RDoc::AnyMethod.new nil, 'method'
    m.parent = @c1
    m.params = 'a'

    assert_equal '(a)', m.param_seq

    m.params = '(a)'

    assert_equal '(a)', m.param_seq

    m.params = "(a,\n  b)"

    assert_equal '(a, b)', m.param_seq

    m.block_params = "c,\n  d"

    assert_equal '(a, b) { |c, d| ... }', m.param_seq
  end

  def test_param_seq_call_seq
    m = RDoc::AnyMethod.new nil, 'method'
    m.parent = @c1

    call_seq = <<-SEQ
method(a) { |c| ... }
method(a, b) { |c, d| ... }
    SEQ

    m.call_seq = call_seq

    assert_equal '(a, b) { |c, d| }', m.param_seq

  end

  def test_parent_name
    assert_equal 'C1', @c1.method_list.first.parent_name
    assert_equal 'C1', @c1.method_list.last.parent_name
  end

  def test_store_equals
    loaded = Marshal.load Marshal.dump(@c1.method_list.last)

    loaded.store = @store

    assert_equal @store, loaded.file.store
  end

  def test_superclass_method
    m3 = RDoc::AnyMethod.new '', 'no_super'

    m2 = RDoc::AnyMethod.new '', 'supers'
    m2.calls_super = true

    m1 = RDoc::AnyMethod.new '', 'supers'

    c1 = RDoc::NormalClass.new 'Outer'
    c1.store = @store
    c1.add_method m1

    c2 = RDoc::NormalClass.new 'Inner', c1
    c2.store = @store
    c2.add_method m2
    c2.add_method m3

    assert_nil m3.superclass_method,
               'no superclass method for no_super'

    assert_equal m1, m2.superclass_method,
                 'superclass method missing for supers'
  end

  def test_superclass_method_multilevel
    m2 = RDoc::AnyMethod.new '', 'supers'
    m2.calls_super = true

    m1 = RDoc::AnyMethod.new '', 'supers'

    c1 = RDoc::NormalClass.new 'Outer'
    c1.store = @store
    c1.add_method m1

    c2 = RDoc::NormalClass.new 'Middle', c1
    c2.store = @store

    c3 = RDoc::NormalClass.new 'Inner', c2
    c3.store = @store
    c3.add_method m2

    assert_equal m1, m2.superclass_method,
                 'superclass method missing for supers'
  end

end

