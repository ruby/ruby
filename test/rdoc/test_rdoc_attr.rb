require 'rubygems'
require 'minitest/autorun'
require 'rdoc/rdoc'

class TestRDocAttr < MiniTest::Unit::TestCase

  def setup
    @a = RDoc::Attr.new nil, 'attr', 'RW', ''
  end

  def test_aref
    m = RDoc::Attr.new nil, 'attr', 'RW', nil

    assert_equal 'attribute-i-attr', m.aref
  end

  def test_arglists
    assert_nil @a.arglists
  end

  def test_block_params
    assert_nil @a.block_params
  end

  def test_call_seq
    assert_nil @a.call_seq
  end

  def test_definition
    assert_equal 'attr_accessor', @a.definition

    @a.rw = 'R'

    assert_equal 'attr_reader', @a.definition

    @a.rw = 'W'

    assert_equal 'attr_writer', @a.definition
  end

  def test_full_name
    assert_equal '(unknown)#attr', @a.full_name
  end

  def test_params
    assert_nil @a.params
  end

  def test_singleton
    refute @a.singleton
  end

  def test_type
    assert_equal 'instance', @a.type

    @a.singleton = true
    assert_equal 'class', @a.type
  end

end

