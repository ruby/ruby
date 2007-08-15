require 'test/unit'

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
end
