require File.expand_path '../xref_test_case', __FILE__

class TestRDocStore < XrefTestCase

  OBJECT_ANCESTORS = defined?(::BasicObject) ? %w[BasicObject] : []

  def setup
    super

    @tmpdir = File.join Dir.tmpdir, "test_rdoc_ri_store_#{$$}"
    @s = RDoc::RI::Store.new @tmpdir
    @s.rdoc = @rdoc

    @top_level = @s.add_file 'file.rb'

    @page = @s.add_file 'README.txt'
    @page.parser = RDoc::Parser::Simple
    @page.comment = RDoc::Comment.new 'This is a page', @page

    @klass = @top_level.add_class RDoc::NormalClass, 'Object'
    @klass.add_comment 'original', @top_level
    @klass.record_location @top_level

    @cmeth = RDoc::AnyMethod.new nil, 'cmethod'
    @cmeth.singleton = true
    @cmeth.record_location @top_level

    @meth_comment = RDoc::Comment.new 'method comment'
    @meth_comment.location = @top_level

    @meth = RDoc::AnyMethod.new nil, 'method'
    @meth.record_location @top_level
    @meth.comment = @meth_comment

    @meth_bang = RDoc::AnyMethod.new nil, 'method!'
    @meth_bang.record_location @top_level

    @meth_bang_alias = RDoc::Alias.new nil, 'method!', 'method_bang', ''
    @meth_bang_alias.record_location @top_level

    @meth_bang.add_alias @meth_bang_alias, @klass

    @attr_comment = RDoc::Comment.new 'attribute comment'
    @attr_comment.location = @top_level

    @attr = RDoc::Attr.new nil, 'attr', 'RW', ''
    @attr.record_location @top_level
    @attr.comment = @attr_comment

    @klass.add_method @cmeth
    @klass.add_method @meth
    @klass.add_method @meth_bang
    @klass.add_attribute @attr

    @nest_klass = @klass.add_class RDoc::NormalClass, 'SubClass'
    @nest_meth = RDoc::AnyMethod.new nil, 'method'
    @nest_meth.record_location @top_level

    @nest_incl = RDoc::Include.new 'Incl', ''
    @nest_incl.record_location @top_level

    @nest_klass.add_method @nest_meth
    @nest_klass.add_include @nest_incl

    @mod = @top_level.add_module RDoc::NormalModule, 'Mod'
    @mod.record_location @top_level
  end

  def teardown
    super

    FileUtils.rm_rf @tmpdir
  end

  def assert_cache imethods, cmethods, attrs, modules,
                   ancestors = {}, pages = [], main = nil, title = nil
    imethods ||= { 'Object' => %w[method method! method_bang] }
    cmethods ||= { 'Object' => %w[cmethod] }
    attrs    ||= { 'Object' => ['attr_accessor attr'] }

    # this is sort-of a hack
    @s.clean_cache_collection ancestors

    expected = {
      :ancestors                   => ancestors,
      :attributes                  => attrs,
      :class_methods               => cmethods,
      :c_class_variables           => {},
      :c_singleton_class_variables => {},
      :encoding                    => nil,
      :instance_methods            => imethods,
      :modules                     => modules,
      :pages                       => pages,
      :main                        => main,
      :title                       => title,
    }

    @s.save_cache

    assert_equal expected, @s.cache
  end

  def test_add_c_enclosure
    @s.add_c_enclosure 'cC1', @c1

    expected = { 'cC1' => @c1 }

    assert_equal expected, @s.c_enclosure_classes
  end

  def test_add_c_variables
    options = RDoc::Options.new

    c_file = @s.add_file 'ext.c'

    some_ext   = c_file.add_class RDoc::NormalClass, 'SomeExt'
                 c_file.add_class RDoc::SingleClass, 'SomeExtSingle'

    c_parser = RDoc::Parser::C.new c_file, 'ext.c', '', options, nil

    c_parser.classes['cSomeExt']             = some_ext
    c_parser.singleton_classes['s_cSomeExt'] = 'SomeExtSingle'

    @s.add_c_variables c_parser

    expected = { 'ext.c' => { 'cSomeExt' => 'SomeExt' } }

    assert_equal expected, @s.c_class_variables

    expected = { 'ext.c' => { 's_cSomeExt' => 'SomeExtSingle' } }

    assert_equal expected, @s.c_singleton_class_variables
  end

  def test_add_file
    top_level = @store.add_file 'file.rb'

    assert_kind_of RDoc::TopLevel, top_level
    assert_equal @store, top_level.store
    assert_equal 'file.rb', top_level.name
    assert_includes @store.all_files, top_level

    assert_same top_level, @store.add_file('file.rb')
    refute_same top_level, @store.add_file('other.rb')
  end

  def test_add_file_relative
    top_level = @store.add_file 'path/file.rb', 'file.rb'

    assert_kind_of RDoc::TopLevel, top_level
    assert_equal @store, top_level.store

    assert_equal 'path/file.rb', top_level.absolute_name
    assert_equal 'file.rb',      top_level.relative_name

    assert_includes @store.all_files, top_level

    assert_same top_level, @store.add_file('file.rb')
    refute_same top_level, @store.add_file('other.rb')
  end

  def test_all_classes_and_modules
    expected = %w[
      C1 C2 C2::C3 C2::C3::H1 C3 C3::H1 C3::H2 C4 C4::C4 C5 C5::C1
      Child
      M1 M1::M2
      Parent
    ]

    assert_equal expected,
                 @store.all_classes_and_modules.map { |m| m.full_name }.sort
  end

  def test_all_files
    assert_equal %w[xref_data.rb],
                 @store.all_files.map { |m| m.full_name }.sort
  end

  def test_all_modules
    assert_equal %w[M1 M1::M2],
                 @store.all_modules.map { |m| m.full_name }.sort
  end

  def test_attributes
    @s.cache[:attributes]['Object'] = %w[attr]

    expected = { 'Object' => %w[attr] }

    assert_equal expected, @s.attributes
  end

  def test_class_file
    assert_equal File.join(@tmpdir, 'Object', 'cdesc-Object.ri'),
                 @s.class_file('Object')
    assert_equal File.join(@tmpdir, 'Object', 'SubClass', 'cdesc-SubClass.ri'),
                 @s.class_file('Object::SubClass')
  end

  def test_class_methods
    @s.cache[:class_methods]['Object'] = %w[method]

    expected = { 'Object' => %w[method] }

    assert_equal expected, @s.class_methods
  end

  def test_class_path
    assert_equal File.join(@tmpdir, 'Object'), @s.class_path('Object')
    assert_equal File.join(@tmpdir, 'Object', 'SubClass'),
                 @s.class_path('Object::SubClass')
  end

  def test_classes
    expected = %w[
      C1 C2 C2::C3 C2::C3::H1 C3 C3::H1 C3::H2 C4 C4::C4 C5 C5::C1
      Child
      Parent
    ]

    assert_equal expected, @store.all_classes.map { |m| m.full_name }.sort
  end

  def test_complete
    @c2.add_module_alias @c2_c3, 'A1', @top_level

    @store.complete :public

    a1 = @xref_data.find_class_or_module 'C2::A1'

    assert_equal 'C2::A1', a1.full_name
    refute_empty a1.aliases
  end

  def test_complete_nodoc
    c_nodoc = @top_level.add_class RDoc::NormalClass, 'Nodoc'
    c_nodoc.record_location @top_level
    c_nodoc.document_self = nil

    @s.complete :nodoc

    assert_includes @s.classes_hash.keys, 'Nodoc'
  end

  def test_find_c_enclosure
    assert_nil @s.find_c_enclosure 'cC1'

    @s.add_c_enclosure 'cC1', @c1

    assert_equal @c1, @s.find_c_enclosure('cC1')
  end

  def test_find_c_enclosure_from_cache
    @s.save_class @klass
    @s.classes_hash.clear

    assert_nil @s.find_c_enclosure 'cObject'

    @s.c_enclosure_names['cObject'] = 'Object'

    klass = @s.find_c_enclosure('cObject')
    assert_equal @klass, klass

    assert_empty klass.comment_location
    assert_equal @top_level, klass.parent

    assert_includes @s.c_enclosure_classes, 'cObject'
  end

  def test_find_c_enclosure_from_cache_legacy
    @klass.in_files.clear
    @s.save_class @klass
    @s.classes_hash.clear

    assert_nil @s.find_c_enclosure 'cObject'

    @s.c_enclosure_names['cObject'] = 'Object'

    assert_nil @s.find_c_enclosure('cObject')
  end

  def test_find_class_named
    assert_equal @c1, @store.find_class_named('C1')

    assert_equal @c2_c3, @store.find_class_named('C2::C3')
  end

  def test_find_class_named_from
    assert_equal @c5_c1, @store.find_class_named_from('C1', 'C5')

    assert_equal @c1,    @store.find_class_named_from('C1', 'C4')
  end

  def test_find_class_or_module
    assert_equal @m1, @store.find_class_or_module('M1')
    assert_equal @c1, @store.find_class_or_module('C1')

    assert_equal @m1, @store.find_class_or_module('::M1')
    assert_equal @c1, @store.find_class_or_module('::C1')
  end

  def test_find_file_named
    assert_equal @xref_data, @store.find_file_named(@file_name)
  end

  def test_find_module_named
    assert_equal @m1,    @store.find_module_named('M1')
    assert_equal @m1_m2, @store.find_module_named('M1::M2')
  end

  def test_find_text_page
    page = @store.add_file 'PAGE.txt'
    page.parser = RDoc::Parser::Simple

    assert_nil @store.find_text_page 'no such page'

    assert_equal page, @store.find_text_page('PAGE.txt')
  end

  def test_friendly_path
    @s.path = @tmpdir
    @s.type = nil
    assert_equal @s.path, @s.friendly_path

    @s.type = :extra
    assert_equal @s.path, @s.friendly_path

    @s.type = :system
    assert_equal "ruby core", @s.friendly_path

    @s.type = :site
    assert_equal "ruby site", @s.friendly_path

    @s.type = :home
    assert_equal "~/.rdoc", @s.friendly_path

    @s.type = :gem
    @s.path = "#{@tmpdir}/gem_repository/doc/gem_name-1.0/ri"
    assert_equal "gem gem_name-1.0", @s.friendly_path
  end

  def test_dry_run
    refute @s.dry_run

    @s.dry_run = true

    assert @s.dry_run
  end

  def test_instance_methods
    @s.cache[:instance_methods]['Object'] = %w[method]

    expected = { 'Object' => %w[method] }

    assert_equal expected, @s.instance_methods
  end

  def test_load_all
    FileUtils.mkdir_p @tmpdir

    @s.save

    s = RDoc::Store.new @tmpdir

    s.load_all

    assert_equal [@klass, @nest_klass], s.all_classes.sort
    assert_equal [@mod],                s.all_modules.sort
    assert_equal [@page, @top_level],   s.all_files.sort

    methods = s.all_classes_and_modules.map do |mod|
      mod.method_list
    end.flatten.sort

    _meth_bang_alias = RDoc::AnyMethod.new nil, 'method_bang'
    _meth_bang_alias.parent = @klass

    assert_equal [@meth, @meth_bang, _meth_bang_alias, @nest_meth, @cmeth],
                 methods.sort_by { |m| m.full_name }

    method = methods.find { |m| m == @meth }
    assert_equal @meth_comment.parse, method.comment

    assert_equal @klass, methods.last.parent

    attributes = s.all_classes_and_modules.map do |mod|
      mod.attributes
    end.flatten.sort

    assert_equal [@attr], attributes

    assert_equal @attr_comment.parse, attributes.first.comment
  end

  def test_load_cache
    cache = {
      :c_class_variables           =>
        { 'file.c' => { 'cKlass' => 'Klass' } },
      :c_singleton_class_variables =>
        { 'file.c' => { 'sKlass' => 'KlassSingle' } },
      :encoding                    => :encoding_value,
      :methods                     => { "Object" => %w[Object#method] },
      :main                        => @page.full_name,
      :modules                     => %w[Object],
      :pages                       => [],
    }

    Dir.mkdir @tmpdir

    open File.join(@tmpdir, 'cache.ri'), 'wb' do |io|
      Marshal.dump cache, io
    end

    @s.load_cache

    assert_equal cache, @s.cache

    assert_equal :encoding_value, @s.encoding
    assert_equal 'README.txt',    @s.main

    expected = { 'file.c' => { 'cKlass' => 'Klass' } }
    assert_equal expected, @s.cache[:c_class_variables]

    expected = { 'file.c' => { 'sKlass' => 'KlassSingle' } }
    assert_equal expected, @s.cache[:c_singleton_class_variables]

    expected = { 'cKlass' => 'Klass' }
    assert_equal expected, @s.c_enclosure_names
  end

  def test_load_cache_encoding_differs
    skip "Encoding not implemented" unless Object.const_defined? :Encoding

    cache = {
      :c_class_variables           => {},
      :c_singleton_class_variables => {},
      :encoding                    => Encoding::ISO_8859_1,
      :main                        => nil,
      :methods                     => { "Object" => %w[Object#method] },
      :modules                     => %w[Object],
      :pages                       => [],
    }

    Dir.mkdir @tmpdir

    open File.join(@tmpdir, 'cache.ri'), 'wb' do |io|
      Marshal.dump cache, io
    end

    @s.encoding = Encoding::UTF_8

    @s.load_cache

    assert_equal cache, @s.cache

    assert_equal Encoding::UTF_8, @s.encoding
  end

  def test_load_cache_no_cache
    cache = {
      :ancestors                   => {},
      :attributes                  => {},
      :class_methods               => {},
      :c_class_variables           => {},
      :c_singleton_class_variables => {},
      :encoding                    => nil,
      :instance_methods            => {},
      :main                        => nil,
      :modules                     => [],
      :pages                       => [],
      :title                       => nil,
    }

    @s.load_cache

    assert_equal cache, @s.cache
  end

  def test_load_cache_legacy
    cache = {
      :ancestors        => {},
      :attributes       => {},
      :class_methods    => {},
      :encoding         => :encoding_value,
      :instance_methods => { "Object" => %w[Object#method] },
      :modules          => %w[Object],
      # no :pages
      # no :main
      # no :c_class_variables
      # no :c_singleton_class_variables
    }

    Dir.mkdir @tmpdir

    open File.join(@tmpdir, 'cache.ri'), 'wb' do |io|
      Marshal.dump cache, io
    end

    @s.load_cache

    expected = {
      :ancestors                   => {},
      :attributes                  => {},
      :class_methods               => {},
      :c_class_variables           => {},
      :c_singleton_class_variables => {},
      :encoding                    => :encoding_value,
      :instance_methods            => { "Object" => %w[Object#method] },
      :main                        => nil,
      :modules                     => %w[Object],
      :pages                       => [],
    }

    assert_equal expected, @s.cache

    assert_equal :encoding_value, @s.encoding
    assert_nil                    @s.main
  end

  def test_load_class
    @s.save_class @klass
    @s.classes_hash.clear

    assert_equal @klass, @s.load_class('Object')

    assert_includes @s.classes_hash, 'Object'
  end

  def test_load_method
    @s.save_method @klass, @meth_bang

    meth = @s.load_method('Object', '#method!')
    assert_equal @meth_bang, meth
    assert_equal @klass, meth.parent
    assert_equal @s, meth.store
  end

  def test_load_method_legacy
    @s.save_method @klass, @meth

    file = @s.method_file @klass.full_name, @meth.full_name

    open file, 'wb' do |io|
      io.write "\x04\bU:\x14RDoc::AnyMethod[\x0Fi\x00I" +
               "\"\vmethod\x06:\x06EF\"\x11Klass#method0:\vpublic" +
               "o:\eRDoc::Markup::Document\x06:\v@parts[\x06" +
               "o:\x1CRDoc::Markup::Paragraph\x06;\t[\x06I" +
               "\"\x16this is a comment\x06;\x06FI" +
               "\"\rcall_seq\x06;\x06FI\"\x0Fsome_block\x06;\x06F" +
               "[\x06[\aI\"\faliased\x06;\x06Fo;\b\x06;\t[\x06" +
               "o;\n\x06;\t[\x06I\"\x12alias comment\x06;\x06FI" +
               "\"\nparam\x06;\x06F"
    end

    meth = @s.load_method('Object', '#method')
    assert_equal 'Klass#method', meth.full_name
    assert_equal @klass,         meth.parent
    assert_equal @s,             meth.store
  end

  def test_load_page
    @s.save_page @page

    assert_equal @page, @s.load_page('README.txt')
  end

  def test_main
    assert_equal nil, @s.main

    @s.main = 'README.txt'

    assert_equal 'README.txt', @s.main
  end

  def test_method_file
    assert_equal File.join(@tmpdir, 'Object', 'method-i.ri'),
                 @s.method_file('Object', 'Object#method')

    assert_equal File.join(@tmpdir, 'Object', 'method%21-i.ri'),
                 @s.method_file('Object', 'Object#method!')

    assert_equal File.join(@tmpdir, 'Object', 'SubClass', 'method%21-i.ri'),
                 @s.method_file('Object::SubClass', 'Object::SubClass#method!')

    assert_equal File.join(@tmpdir, 'Object', 'method-c.ri'),
                 @s.method_file('Object', 'Object::method')
  end

  def test_module_names
    @s.save_class @klass

    assert_equal %w[Object], @s.module_names
  end

  def test_page
    page = @store.add_file 'PAGE.txt'
    page.parser = RDoc::Parser::Simple

    assert_nil @store.page 'no such page'

    assert_equal page, @store.page('PAGE')
  end

  def test_save
    FileUtils.mkdir_p @tmpdir

    @s.save

    assert_directory File.join(@tmpdir, 'Object')

    assert_file File.join(@tmpdir, 'Object', 'cdesc-Object.ri')
    assert_file File.join(@tmpdir, 'Object', 'method-i.ri')
    assert_file File.join(@tmpdir, 'page-README_txt.ri')

    assert_file File.join(@tmpdir, 'cache.ri')

    expected = {
      :ancestors => {
        'Object::SubClass' => %w[Incl Object],
      },
      :attributes => { 'Object' => ['attr_accessor attr'] },
      :class_methods => { 'Object' => %w[cmethod] },
      :c_class_variables => {},
      :c_singleton_class_variables => {},
      :instance_methods => {
        'Object' => %w[attr method method! method_bang],
        'Object::SubClass' => %w[method],
      },
      :main => nil,
      :modules => %w[Mod Object Object::SubClass],
      :encoding => nil,
      :pages => %w[README.txt],
      :title => nil,
    }

    expected[:ancestors]['Object'] = %w[BasicObject] if defined?(::BasicObject)

    open File.join(@tmpdir, 'cache.ri'), 'rb' do |io|
      cache = Marshal.load io.read

      assert_equal expected, cache
    end
  end

  def test_save_cache
    @s.save_class @klass
    @s.save_method @klass, @meth
    @s.save_method @klass, @cmeth
    @s.save_class @nest_klass
    @s.save_page @page
    @s.encoding = :encoding_value
    @s.main     = @page.full_name
    @s.title    = 'title'

    options = RDoc::Options.new

    c_file = @s.add_file 'ext.c'

    some_ext   = c_file.add_class RDoc::NormalClass, 'SomeExt'
                 c_file.add_class RDoc::SingleClass, 'SomeExtSingle'

    c_parser = RDoc::Parser::C.new c_file, 'ext.c', '', options, nil

    c_parser.classes['cSomeExt']             = some_ext
    c_parser.singleton_classes['s_cSomeExt'] = 'SomeExtSingle'

    @s.add_c_variables c_parser

    @s.save_cache

    assert_file File.join(@tmpdir, 'cache.ri')

    c_class_variables = {
      'ext.c' => {
        'cSomeExt' => 'SomeExt'
      }
    }

    c_singleton_class_variables = {
      'ext.c' => {
        's_cSomeExt' => 'SomeExtSingle'
      }
    }

    expected = {
      :ancestors => {
        'Object::SubClass' => %w[Incl Object],
      },
      :attributes => { 'Object' => ['attr_accessor attr'] },
      :class_methods => { 'Object' => %w[cmethod] },
      :c_class_variables => c_class_variables,
      :c_singleton_class_variables => c_singleton_class_variables,
      :instance_methods => {
        'Object' => %w[method method! method_bang],
        'Object::SubClass' => %w[method],
      },
      :main => @page.full_name,
      :modules => %w[Object Object::SubClass],
      :encoding => :encoding_value,
      :pages => %w[README.txt],
      :title => 'title',
    }

    expected[:ancestors]['Object'] = %w[BasicObject] if defined?(::BasicObject)

    open File.join(@tmpdir, 'cache.ri'), 'rb' do |io|
      cache = Marshal.load io.read

      assert_equal expected, cache
    end
  end

  def test_save_cache_dry_run
    @s.dry_run = true

    @s.save_class @klass
    @s.save_method @klass, @meth
    @s.save_method @klass, @cmeth
    @s.save_class @nest_klass

    @s.save_cache

    refute_file File.join(@tmpdir, 'cache.ri')
  end

  def test_save_cache_duplicate_methods
    @s.save_method @klass, @meth
    @s.save_method @klass, @meth

    @s.save_cache

    assert_cache({ 'Object' => %w[method] }, {}, {}, [])
  end

  def test_save_cache_duplicate_pages
    @s.save_page @page
    @s.save_page @page

    @s.save_cache

    assert_cache({}, {}, {}, [], {}, %w[README.txt])
  end

  def test_save_class
    @s.save_class @klass

    assert_directory File.join(@tmpdir, 'Object')
    assert_file File.join(@tmpdir, 'Object', 'cdesc-Object.ri')

    assert_cache nil, nil, nil, %w[Object], 'Object' => OBJECT_ANCESTORS

    assert_equal @klass, @s.load_class('Object')
  end

  def test_save_class_basic_object
    @klass.instance_variable_set :@superclass, nil

    @s.save_class @klass

    assert_directory File.join(@tmpdir, 'Object')
    assert_file File.join(@tmpdir, 'Object', 'cdesc-Object.ri')

    assert_cache(nil, nil, nil, %w[Object])

    assert_equal @klass, @s.load_class('Object')
  end

  def test_save_class_delete
    # save original
    @s.save_class @klass
    @s.save_method @klass, @meth
    @s.save_method @klass, @meth_bang
    @s.save_method @klass, @cmeth
    @s.save_method @klass, @attr
    @s.save_cache

    klass = RDoc::NormalClass.new 'Object'

    meth = klass.add_method RDoc::AnyMethod.new(nil, 'replace')
    meth.record_location @top_level

    # load original, save newly updated class
    @s = RDoc::RI::Store.new @tmpdir
    @s.load_cache
    @s.save_class klass
    @s.save_cache

    # load from disk again
    @s = RDoc::RI::Store.new @tmpdir
    @s.load_cache

    @s.load_class 'Object'

    assert_cache({ 'Object' => %w[replace] }, {},
                 { 'Object' => %w[attr_accessor\ attr] }, %w[Object],
                   'Object' => OBJECT_ANCESTORS)

    # assert these files were deleted
    refute_file @s.method_file(@klass.full_name, @meth.full_name)
    refute_file @s.method_file(@klass.full_name, @meth_bang.full_name)
    refute_file @s.method_file(@klass.full_name, @cmeth.full_name)

    # assert these files were not deleted
    assert_file @s.method_file(@klass.full_name, @attr.full_name)
  end

  def test_save_class_dry_run
    @s.dry_run = true

    @s.save_class @klass

    refute_file File.join(@tmpdir, 'Object')
    refute_file File.join(@tmpdir, 'Object', 'cdesc-Object.ri')
  end

  def test_save_class_loaded
    @s.save

    assert_directory File.join(@tmpdir, 'Object')
    assert_file      File.join(@tmpdir, 'Object', 'cdesc-Object.ri')

    assert_file @s.method_file(@klass.full_name, @attr.full_name)
    assert_file @s.method_file(@klass.full_name, @cmeth.full_name)
    assert_file @s.method_file(@klass.full_name, @meth.full_name)
    assert_file @s.method_file(@klass.full_name, @meth_bang.full_name)

    s = RDoc::Store.new @s.path
    s.load_cache

    loaded = s.load_class 'Object'

    assert_equal @klass, loaded

    s.save_class loaded

    s = RDoc::Store.new @s.path
    s.load_cache

    reloaded = s.load_class 'Object'

    assert_equal @klass, reloaded

    # assert these files were not deleted.  Bug #171
    assert_file s.method_file(@klass.full_name, @attr.full_name)
    assert_file s.method_file(@klass.full_name, @cmeth.full_name)
    assert_file s.method_file(@klass.full_name, @meth.full_name)
    assert_file s.method_file(@klass.full_name, @meth_bang.full_name)
  end

  def test_save_class_merge
    @s.save_class @klass

    klass = RDoc::NormalClass.new 'Object'
    klass.add_comment 'new comment', @top_level

    s = RDoc::RI::Store.new @tmpdir
    s.save_class klass

    s = RDoc::RI::Store.new @tmpdir

    inner = @RM::Document.new @RM::Paragraph.new 'new comment'
    inner.file = @top_level

    document = @RM::Document.new inner

    assert_equal document, s.load_class('Object').comment_location
  end

  # This is a functional test
  def test_save_class_merge_constant
    store = RDoc::Store.new
    tl = store.add_file 'file.rb'

    klass = tl.add_class RDoc::NormalClass, 'C'
    klass.add_comment 'comment', tl

    const = klass.add_constant RDoc::Constant.new('CONST', nil, nil)
    const.record_location tl

    @s.save_class klass

    # separate parse run, independent store
    store = RDoc::Store.new
    tl = store.add_file 'file.rb'
    klass2 = tl.add_class RDoc::NormalClass, 'C'
    klass2.record_location tl

    s = RDoc::RI::Store.new @tmpdir
    s.save_class klass2

    # separate `ri` run, independent store
    s = RDoc::RI::Store.new @tmpdir

    result = s.load_class 'C'

    assert_empty result.constants
  end

  def test_save_class_methods
    @s.save_class @klass

    assert_directory File.join(@tmpdir, 'Object')
    assert_file File.join(@tmpdir, 'Object', 'cdesc-Object.ri')

    assert_cache nil, nil, nil, %w[Object], 'Object' => OBJECT_ANCESTORS

    assert_equal @klass, @s.load_class('Object')
  end

  def test_save_class_nested
    @s.save_class @nest_klass

    assert_directory File.join(@tmpdir, 'Object', 'SubClass')
    assert_file File.join(@tmpdir, 'Object', 'SubClass', 'cdesc-SubClass.ri')

    assert_cache({ 'Object::SubClass' => %w[method] }, {}, {},
                 %w[Object::SubClass], 'Object::SubClass' => %w[Incl Object])
  end

  def test_save_method
    @s.save_method @klass, @meth

    assert_directory File.join(@tmpdir, 'Object')
    assert_file File.join(@tmpdir, 'Object', 'method-i.ri')

    assert_cache({ 'Object' => %w[method] }, {}, {}, [])

    assert_equal @meth, @s.load_method('Object', '#method')
  end

  def test_save_method_dry_run
    @s.dry_run = true

    @s.save_method @klass, @meth

    refute_file File.join(@tmpdir, 'Object')
    refute_file File.join(@tmpdir, 'Object', 'method-i.ri')
  end

  def test_save_method_nested
    @s.save_method @nest_klass, @nest_meth

    assert_directory File.join(@tmpdir, 'Object', 'SubClass')
    assert_file File.join(@tmpdir, 'Object', 'SubClass', 'method-i.ri')

    assert_cache({ 'Object::SubClass' => %w[method] }, {}, {}, [])
  end

  def test_save_page
    @s.save_page @page

    assert_file File.join(@tmpdir, 'page-README_txt.ri')

    assert_cache({}, {}, {}, [], {}, %w[README.txt])
  end

  def test_save_page_file
    @s.save_page @top_level

    refute_file File.join(@tmpdir, 'page-file_rb.ri')
  end

  def test_source
    @s.path = @tmpdir
    @s.type = nil
    assert_equal @s.path, @s.source

    @s.type = :extra
    assert_equal @s.path, @s.source

    @s.type = :system
    assert_equal "ruby", @s.source

    @s.type = :site
    assert_equal "site", @s.source

    @s.type = :home
    assert_equal "home", @s.source

    @s.type = :gem
    @s.path = "#{@tmpdir}/gem_repository/doc/gem_name-1.0/ri"
    assert_equal "gem_name-1.0", @s.source
  end

  def test_title
    assert_equal nil, @s.title

    @s.title = 'rdoc'

    assert_equal 'rdoc', @s.title
  end

end

