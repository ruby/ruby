require 'test/unit'
require 'soap/baseData'
require 'soap/mapping'


module SOAP


class TestSOAPElement < Test::Unit::TestCase
  include SOAP

  def setup
    # Nothing to do.
  end

  def teardown
    # Nothing to do.
  end

  def d(elename = nil, text = nil)
    elename ||= n(nil, nil)
    if text
      SOAPElement.new(elename, text)
    else
      SOAPElement.new(elename)	# do not merge.
    end
  end

  def n(namespace, name)
    XSD::QName.new(namespace, name)
  end

  def test_initialize
    elename = n(nil, nil)
    obj = d(elename)
    assert_equal(elename, obj.elename)
    assert_equal(LiteralNamespace, obj.encodingstyle)
    assert_equal({}, obj.extraattr)
    assert_equal([], obj.precedents)
    assert_equal(nil, obj.qualified)
    assert_equal(nil, obj.text)
    assert(obj.members.empty?)

    obj = d("foo", "text")
    assert_equal(n(nil, "foo"), obj.elename)
    assert_equal("text", obj.text)
  end

  def test_add
    obj = d()
    child = d("abc")
    obj.add(child)
    assert(obj.key?("abc"))
    assert_same(child, obj["abc"])
    assert_same(child, obj.abc)
    def obj.foo; 1; end
    child = d("foo")
    obj.add(child)
    assert_equal(1, obj.foo)
    assert_equal(child, obj.var_foo)
    child = d("_?a?b_")
    obj.add(child)
    assert_equal(child, obj.__send__('_?a?b_'))
  end

  def test_member
    obj = d()
    c1 = d("c1")
    obj.add(c1)
    c2 = d("c2")
    obj.add(c2)
    assert(obj.key?("c1"))
    assert(obj.key?("c2"))
    assert_equal(c1, obj["c1"])
    assert_equal(c2, obj["c2"])
    c22 = d("c22")
    obj["c2"] = c22
    assert(obj.key?("c2"))
    assert_equal(c22, obj["c2"])
    assert_equal(["c1", "c2"], obj.members.sort)
    #
    k_expect = ["c1", "c2"]
    v_expect = [c1, c22]
    obj.each do |k, v|
      assert(k_expect.include?(k))
      assert(v_expect.include?(v))
      k_expect.delete(k)
      v_expect.delete(v)
    end
    assert(k_expect.empty?)
    assert(v_expect.empty?)
  end

  def test_to_obj
    obj = d("root")
    ct1 = d("ct1", "t1")
    obj.add(ct1)
    c2 = d("c2")
    ct2 = d("ct2", "t2")
    c2.add(ct2)
    obj.add(c2)
    assert_equal({ "ct1" => "t1", "c2" => { "ct2" => "t2" }}, obj.to_obj)
    #
    assert_equal(nil, d().to_obj)
    assert_equal("abc", d(nil, "abc").to_obj)
    assert_equal(nil, d("abc", nil).to_obj)
  end

  def test_from_obj
    source = { "ct1" => "t1", "c2" => { "ct2" => "t2" }}
    assert_equal(source, SOAPElement.from_obj(source).to_obj)
    source = { "1" => nil }
    assert_equal(source, SOAPElement.from_obj(source).to_obj)
    source = {}
    assert_equal(nil, SOAPElement.from_obj(source).to_obj)	# not {}
    source = nil
    assert_equal(nil, SOAPElement.from_obj(source).to_obj)
  end
end


end
