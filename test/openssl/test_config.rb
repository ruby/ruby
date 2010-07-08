require 'openssl'
require "test/unit"
require 'tempfile'
require File.join(File.dirname(__FILE__), "utils.rb")

class OpenSSL::TestConfig < Test::Unit::TestCase
  def setup
    file = Tempfile.open("openssl.cnf")
    file << <<__EOD__
HOME = .
[ ca ]
default_ca = CA_default
[ CA_default ]
dir = ./demoCA
certs                =                  ./certs
__EOD__
    file.close
    @it = OpenSSL::Config.new(file.path)
  end

  def test_initialize
    c = OpenSSL::Config.new
    assert_equal("", c.to_s)
    assert_equal([], c.sections)
  end

  def test_initialize_with_empty_file
    file = Tempfile.open("openssl.cnf")
    file.close
    c = OpenSSL::Config.new(file.path)
    assert_equal("[ default ]\n\n", c.to_s)
    assert_equal(['default'], c.sections)
  end

  def test_initialize_with_example_file
    assert_equal(['CA_default', 'ca', 'default'], @it.sections.sort)
  end

  def test_get_value
    assert_equal('CA_default', @it.get_value('ca', 'default_ca'))
    assert_equal(nil, @it.get_value('ca', 'no such key'))
    assert_equal(nil, @it.get_value('no such section', 'no such key'))
    assert_equal('.', @it.get_value('', 'HOME'))
    assert_raise(TypeError) do
      @it.get_value(nil, 'HOME') # not allowed unlike Config#value
    end
  end

  def test_value
    # supress deprecation warnings
    OpenSSL::TestUtils.silent do
      assert_equal('CA_default', @it.value('ca', 'default_ca'))
      assert_equal(nil, @it.value('ca', 'no such key'))
      assert_equal(nil, @it.value('no such section', 'no such key'))
      assert_equal('.', @it.value('', 'HOME'))
      assert_equal('.', @it.value(nil, 'HOME'))
      assert_equal('.', @it.value('HOME'))
    end
  end

  def test_aref
    assert_equal({'HOME' => '.'}, @it['default'])
    assert_equal({'dir' => './demoCA', 'certs' => './certs'}, @it['CA_default'])
    assert_equal({}, @it['no_such_section'])
    assert_equal({}, @it[''])
  end

  def test_section
    OpenSSL::TestUtils.silent do
      assert_equal({'HOME' => '.'}, @it.section('default'))
      assert_equal({'dir' => './demoCA', 'certs' => './certs'}, @it.section('CA_default'))
      assert_equal({}, @it.section('no_such_section'))
      assert_equal({}, @it.section(''))
    end
  end

  def test_sections
    assert_equal(['CA_default', 'ca', 'default'], @it.sections.sort)
    @it['new_section'] = {'foo' => 'bar'}
    assert_equal(['CA_default', 'ca', 'default', 'new_section'], @it.sections.sort)
    @it['new_section'] = {}
    assert_equal(['CA_default', 'ca', 'default', 'new_section'], @it.sections.sort)
  end

  def test_add_value
    c = OpenSSL::Config.new
    assert_equal("", c.to_s)
    # add key
    c.add_value('default', 'foo', 'bar')
    assert_equal("[ default ]\nfoo=bar\n\n", c.to_s)
    # add another key
    c.add_value('default', 'baz', 'qux')
    assert_equal("[ default ]\nfoo=bar\nbaz=qux\n\n", c.to_s)
    # update the value
    c.add_value('default', 'baz', 'quxxx')
    assert_equal("[ default ]\nfoo=bar\nbaz=quxxx\n\n", c.to_s)
    # add section and key
    c.add_value('section', 'foo', 'bar')
    assert_equal("[ default ]\nfoo=bar\nbaz=quxxx\n\n[ section ]\nfoo=bar\n\n", c.to_s)
  end

  def test_aset
    @it['foo'] = {'bar' => 'baz'}
    assert_equal({'bar' => 'baz'}, @it['foo'])
    @it['foo'] = {'bar' => 'qux', 'baz' => 'quxx'}
    assert_equal({'bar' => 'qux', 'baz' => 'quxx'}, @it['foo'])

    # OpenSSL::Config is add only for now.
    @it['foo'] = {'foo' => 'foo'}
    assert_equal({'foo' => 'foo', 'bar' => 'qux', 'baz' => 'quxx'}, @it['foo'])
    # you cannot override or remove any section and key.
    @it['foo'] = {}
    assert_equal({'foo' => 'foo', 'bar' => 'qux', 'baz' => 'quxx'}, @it['foo'])
  end

  def test_each
    # each returns [section, key, value] array.
    ary = @it.map { |e| e }.sort { |a, b| a[0] <=> b[0] }
    assert_equal(4, ary.size)
    assert_equal('CA_default', ary[0][0])
    assert_equal('CA_default', ary[1][0])
    assert_equal(["ca", "default_ca", "CA_default"], ary[2])
    assert_equal(["default", "HOME", "."], ary[3])
  end

  def test_inspect
    assert_nothing_raised do
      @it.inspect
    end
  end

  def test_freeze
    c = OpenSSL::Config.new
    c['foo'] = [['key', 'value']]
    c.freeze

    # [ruby-core:18377]
    # RuntimeError for 1.9, TypeError for 1.8
    assert_raise(TypeError, /frozen/) do
      c['foo'] = [['key', 'wrong']]
    end
  end
end
