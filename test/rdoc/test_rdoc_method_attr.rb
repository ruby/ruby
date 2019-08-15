# frozen_string_literal: true
require File.expand_path '../xref_test_case', __FILE__

class TestRDocMethodAttr < XrefTestCase

  def test_initialize_copy
    refute_same @c1_m.full_name, @c1_m.dup.full_name
  end

  def test_block_params_equal
    m = RDoc::MethodAttr.new(nil, 'foo')

    m.block_params = ''
    assert_equal '', m.block_params

    m.block_params = 'a_var'
    assert_equal 'a_var', m.block_params

    m.block_params = '()'
    assert_equal '', m.block_params

    m.block_params = '(a_var, b_var)'
    assert_equal 'a_var, b_var', m.block_params

    m.block_params = '.to_s + "</#{element.upcase}>"'
    assert_equal '', m.block_params

    m.block_params = 'i.name'
    assert_equal 'name', m.block_params

    m.block_params = 'attr.expanded_name, attr.value'
    assert_equal 'expanded_name, value', m.block_params

    m.block_params = 'expanded_name, attr.value'
    assert_equal 'expanded_name, value', m.block_params

    m.block_params = 'attr.expanded_name, value'
    assert_equal 'expanded_name, value', m.block_params

    m.block_params = '(@base_notifier)'
    assert_equal 'base_notifier', m.block_params

    m.block_params = 'if @signal_status == :IN_LOAD'
    assert_equal '', m.block_params

    m.block_params = 'e if e.kind_of? Element'
    assert_equal 'e', m.block_params

    m.block_params = '(e, f) if e.kind_of? Element'
    assert_equal 'e, f', m.block_params

    m.block_params = 'back_path, back_name'
    assert_equal 'back_path, back_name', m.block_params

    m.block_params = '(*a[1..-1])'
    assert_equal '*a', m.block_params

    m.block_params = '@@context[:node] if defined? @@context[:node].namespace'
    assert_equal 'context', m.block_params

    m.block_params = '(result, klass.const_get(constant_name))'
    assert_equal 'result, const', m.block_params

    m.block_params = 'name.to_s if (bitmap & bit) != 0'
    assert_equal 'name', m.block_params

    m.block_params = 'line unless line.deleted'
    assert_equal 'line', m.block_params

    m.block_params = 'str + rs'
    assert_equal 'str', m.block_params

    m.block_params = 'f+rs'
    assert_equal 'f', m.block_params

    m.block_params = '[user, realm, hash[user]]'
    assert_equal 'user, realm, hash', m.block_params

    m.block_params = 'proc{|rc| rc == "rc" ? irbrc : irbrc+rc| ... }'
    assert_equal 'proc', m.block_params

    m.block_params = 'lambda { |x| x.to_i }'
    assert_equal 'lambda', m.block_params

    m.block_params = '$&'
    assert_equal 'str', m.block_params

    m.block_params = 'Inflections.instance'
    assert_equal 'instance', m.block_params

    m.block_params = 'self.class::STARTED'
    assert_equal 'STARTED', m.block_params

    m.block_params = 'Test::Unit::TestCase::STARTED'
    assert_equal 'STARTED', m.block_params

    m.block_params = 'ActiveSupport::OptionMerger.new(self, options)'
    assert_equal 'option_merger', m.block_params

    m.block_params = ', msg'
    assert_equal '', m.block_params

    m.block_params = '[size.to_s(16), term, chunk, term].join'
    assert_equal '[size, term, chunk, term].join', m.block_params

    m.block_params = 'YPath.new( path )'
    assert_equal 'y_path', m.block_params

  end

  def test_find_method_or_attribute_recursive
    inc = RDoc::Include.new 'M1', nil
    @m1.add_include inc # M1 now includes itself

    assert_nil @m1_m.find_method_or_attribute 'm'
  end

  def test_full_name
    assert_equal 'C1#m',  @c1_m.full_name
    assert_equal 'C1::m', @c1__m.full_name
  end

  def test_is_alias_for
    assert_equal @c2_b, @c2_a.is_alias_for
  end

  def test_output_name
    assert_equal '#m',  @c1_m.output_name(@c1)
    assert_equal '::m', @c1__m.output_name(@c1)

    assert_equal 'C1#m', @c1_m.output_name(@c2)
    assert_equal 'C1.m', @c1__m.output_name(@c2)
  end

  def test_search_record
    @c1_m.comment = 'This is a comment.'

    expected = [
      'm',
      'C1#m',
      'm',
      'C1',
      'C1.html#method-i-m',
      '(foo)',
      "<p>This is a comment.\n",
    ]

    assert_equal expected, @c1_m.search_record
  end

  def test_spaceship
    assert_nil @c1_m.<=>(RDoc::CodeObject.new)
  end

  def test_equals2
    assert_equal @c1_m, @c1_m
    refute_equal @c1_m, @parent_m
  end

  def test_pretty_print
    temp_dir do |tmpdir|
      s = RDoc::RI::Store.new tmpdir
      s.rdoc = @rdoc

      top_level = s.add_file 'file.rb'
      meth_bang = RDoc::AnyMethod.new nil, 'method!'
      meth_bang.record_location top_level

      meth_bang_alias = RDoc::Alias.new nil, 'method!', 'method_bang', ''
      meth_bang_alias.record_location top_level

      klass = top_level.add_class RDoc::NormalClass, 'Object'
      klass.add_method meth_bang

      meth_bang.add_alias meth_bang_alias, klass

      s.save

      meth_alias_from_store = s.load_method 'Object', '#method_bang'

      expected = "[RDoc::AnyMethod Object#method_bang public alias for method!]"
      actual =  mu_pp meth_alias_from_store
      assert_equal expected, actual
    end
  end

  def test_to_s
    assert_equal 'RDoc::AnyMethod: C1#m',  @c1_m.to_s
    assert_equal 'RDoc::AnyMethod: C2#b',  @c2_b.to_s
    assert_equal 'RDoc::AnyMethod: C1::m', @c1__m.to_s
  end

end

