require 'test/unit'

class TestLambdaParameters < Test::Unit::TestCase
  def test_call_simple
    assert_equal(1, ->(a){ a }.call(1))
    assert_equal([1,2], ->(a,b){ [a,b] }.call(1,2))
    assert_raises(ArgumentError) { ->(a){ }.call(1,2) }
    assert_raises(ArgumentError) { ->(a){ }.call() }
    assert_raises(ArgumentError) { ->(){ }.call(1) }
    assert_raises(ArgumentError) { ->(a,b){ }.call(1,2,3) }
  end

  def test_call_rest_args
    assert_equal([1,2], ->(*a){ a }.call(1,2))
    assert_equal([1,2,[]], ->(a,b,*c){ [a,b,c] }.call(1,2))
    assert_raises(ArgumentError){ ->(a,*b){ }.call() }
  end

  def test_call_opt_args
    assert_equal([1,2,3,4], ->(a,b,c=3,d=4){ [a,b,c,d] }.call(1,2))
    assert_equal([1,2,3,4], ->(a,b,c=0,d=4){ [a,b,c,d] }.call(1,2,3))
    assert_raises(ArgumentError){ ->(a,b=1){ }.call() }
    assert_raises(ArgumentError){ ->(a,b=1){ }.call(1,2,3) }
  end

  def test_call_rest_and_opt
    assert_equal([1,2,3,[]], ->(a,b=2,c=3,*d){ [a,b,c,d] }.call(1))
    assert_equal([1,2,3,[]], ->(a,b=0,c=3,*d){ [a,b,c,d] }.call(1,2))
    assert_equal([1,2,3,[4,5,6]], ->(a,b=0,c=0,*d){ [a,b,c,d] }.call(1,2,3,4,5,6))
    assert_raises(ArgumentError){ ->(a,b=1,*c){ }.call() }
  end

  def test_call_with_block
    f = ->(a,b,c=3,*d,&e){ [a,b,c,d,e.call(d + [a,b,c])] }
    assert_equal([1,2,3,[],6], f.call(1,2){|z| z.inject{|s,x| s+x} } )
    assert_equal(nil, ->(&b){ b }.call)
    foo { puts "bogus block " }
    assert_equal(1, ->(&b){ b.call }.call { 1 })
    b = nil
    assert_equal(1, ->(&b){ b.call }.call { 1 })
    assert_not_nil(b)
  end

  def foo
    assert_equal(nil, ->(&b){ b }.call)
  end

  def test_lambda_as_iterator
    a = 0
    2.times ->(_){ a += 1 }
    assert_equal(a, 2)
  end
end
