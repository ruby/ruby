require 'test/unit'

class TestEnv < Test::Unit::TestCase
  IGNORE_CASE = /djgpp|bccwin|mswin|mingw/ =~ RUBY_PLATFORM

  def setup
    @backup = ENV.delete('test')
    @BACKUP = ENV.delete('TEST')
  end

  def teardown
    ENV['test'] = @backup if @backup
    ENV['TEST'] = @BACKUP if @BACKUP
  end

  def test_bracket
    assert_nil(ENV['test'])
    assert_nil(ENV['TEST'])
    ENV['test'] = 'foo'
    assert_equal('foo', ENV['test'])
    if IGNORE_CASE
      assert_equal('foo', ENV['TEST'])
    else
      assert_nil(ENV['TEST'])
    end
    ENV['TEST'] = 'bar'
    assert_equal('bar', ENV['TEST'])
    if IGNORE_CASE
      assert_equal('bar', ENV['test'])
    else
      assert_equal('foo', ENV['test'])
    end

    assert_raises(TypeError) {
      tmp = ENV[1]
    }
    assert_raises(TypeError) {
      ENV[1] = 'foo'
    }
    assert_raises(TypeError) {
      ENV['test'] = 0
    }
  end

  def test_has_value
    val = 'a'
    val.succ! while ENV.has_value?(val) && ENV.has_value?(val.upcase)
    ENV['test'] = val[0...-1]

    assert_equal(false, ENV.has_value?(val))
    assert_equal(false, ENV.has_value?(val.upcase))
    ENV['test'] = val
    assert_equal(true, ENV.has_value?(val))
    assert_equal(false, ENV.has_value?(val.upcase))
    ENV['test'] = val.upcase
    assert_equal(false, ENV.has_value?(val))
    assert_equal(true, ENV.has_value?(val.upcase))
  end

  def test_index
    val = 'a'
    val.succ! while ENV.has_value?(val) && ENV.has_value?(val.upcase)
    ENV['test'] = val[0...-1]

    assert_nil(ENV.index(val))
    assert_nil(ENV.index(val.upcase))
    ENV['test'] = val
    if IGNORE_CASE
      assert_equal('TEST', ENV.index(val).upcase)
    else
      assert_equal('test', ENV.index(val))
    end
    assert_nil(ENV.index(val.upcase))
    ENV['test'] = val.upcase
    assert_nil(ENV.index(val))
    if IGNORE_CASE
      assert_equal('TEST', ENV.index(val.upcase).upcase)
    else
      assert_equal('test', ENV.index(val.upcase))
    end
  end
end
