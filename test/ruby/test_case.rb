require 'test/unit'
require 'envutil.rb'

class TestCase < Test::Unit::TestCase
  def test_case
    case 5
    when 1, 2, 3, 4, 6, 7, 8
      assert(false)
    when 5
      assert(true)
    end

    case 5
    when 5
      assert(true)
    when 1..10
      assert(false)
    end

    case 5
    when 1..10
      assert(true)
    else
      assert(false)
    end

    case 5
    when 5
      assert(true)
    else
      assert(false)
    end

    case "foobar"
    when /^f.*r$/
      assert(true)
    else
      assert(false)
    end

    case
    when true
      assert(true)
    when false, nil
      assert(false)
    else
      assert(false)
    end
  end

  def test_deoptimization
    assert_in_out_err(['-e', <<-EOS], '', %w[42], [])
      class Symbol; def ===(o); p 42; true; end; end; case :foo; when :foo; end
    EOS

    assert_in_out_err(['-e', <<-EOS], '', %w[42], [])
      class Fixnum; def ===(o); p 42; true; end; end; case 1; when 1; end
    EOS
  end
end
