require 'test/unit'
require 'rinda/tuplespace'

class Rinda::TupleBag
  attr_reader :hash
end

class TestTupleBag < Test::Unit::TestCase

  def setup
    @tb = Rinda::TupleBag.new
  end

  def test_delete
    assert_nothing_raised do
      val = @tb.delete tup(:val, 1)
      assert_equal nil, val
    end

    t = tup(:val, 1)
    @tb.push t

    val = @tb.delete t

    assert_equal t, val
  end

  def test_delete_unless_alive
    assert_equal [], @tb.delete_unless_alive

    t1 = tup(:val, nil)
    t2 = tup(:val, nil)

    @tb.push t1
    @tb.push t2

    assert_equal [], @tb.delete_unless_alive

    t1.cancel

    assert_equal [t1], @tb.delete_unless_alive, 'canceled'

    t2.renew Object.new

    assert_equal [t2], @tb.delete_unless_alive, 'expired'
  end

  def test_find
    template = tem(:val, nil)

    assert_equal nil, @tb.find(template)

    t1 = tup(:val, 1)
    t2 = tup(:val, 2)

    @tb.push t1
    @tb.push t2

    assert_equal t1, @tb.find(template)

    t1.cancel

    assert_equal t2, @tb.find(template), 'canceled'

    t2.renew Object.new

    assert_equal nil, @tb.find(template), 'expired'
  end

  def test_find_all
    template = tem(:val, nil)

    assert_equal [], @tb.find_all(template)

    t1 = tup(:val, 1)
    t2 = tup(:val, 2)

    @tb.push t1
    @tb.push t2

    assert_equal [t1, t2], @tb.find_all(template)

    t1.cancel

    assert_equal [t2], @tb.find_all(template), 'canceled'

    t2.renew Object.new

    assert_equal [], @tb.find_all(template), 'expired'
  end

  def test_find_all_template
    tuple = tup(:val, 1)

    assert_equal [], @tb.find_all_template(tuple)

    t1 = tem(:val, nil)
    t2 = tem(:val, nil)

    @tb.push t1
    @tb.push t2

    assert_equal [t1, t2], @tb.find_all_template(tuple)

    t1.cancel

    assert_equal [t2], @tb.find_all_template(tuple), 'canceled'

    t2.renew Object.new

    assert_equal [], @tb.find_all_template(tuple), 'expired'
  end

  def test_has_expires_eh
    assert_equal false, @tb.has_expires?

    t = tup(:val, 1)
    @tb.push t

    assert_equal true, @tb.has_expires?

    t.renew Object.new

    assert_equal false, @tb.has_expires?
  end

  def test_push
    t = tup(:val, 1)

    @tb.push t
    
    assert_equal t, @tb.find(tem(:val, 1))
  end

  ##
  # Create a tuple with +ary+ for its contents

  def tup(*ary)
    Rinda::TupleEntry.new ary
  end

  ##
  # Create a template with +ary+ for its contents

  def tem(*ary)
    Rinda::TemplateEntry.new ary
  end

end

