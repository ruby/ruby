require 'test/unit'
require 'date'

class TestDateMarshal < Test::Unit::TestCase

  def test_marshal
    d = Date.new
    m = Marshal.dump(d)
    d2 = Marshal.load(m)
    assert_equal(d, d2)
    assert_equal(d.start, d2.start)
    assert_instance_of(String, d2.to_s)

    d = Date.today
    m = Marshal.dump(d)
    d2 = Marshal.load(m)
    assert_equal(d, d2)
    assert_equal(d.start, d2.start)
    assert_instance_of(String, d2.to_s)

    d = DateTime.now
    m = Marshal.dump(d)
    d2 = Marshal.load(m)
    assert_equal(d, d2)
    assert_equal(d.start, d2.start)
    assert_instance_of(String, d2.to_s)

    d = Date.today
    a = d.marshal_dump
    d.freeze
    assert(d.frozen?)
    assert_raise(RuntimeError){d.marshal_load(a)}

    d = DateTime.now
    a = d.marshal_dump
    d.freeze
    assert(d.frozen?)
    assert_raise(RuntimeError){d.marshal_load(a)}
  end

  def test_marshal_old
    bug6652 = '[ruby-core:45891]'

    data = "\004\bu:\tDate=\004\b[\bo:\rRational\a:\017@numeratori\003%\275J:\021" \
           "@denominatori\ai\000i\003\031\025#"
    assert_equal(Date.new(1993, 2, 24), Marshal.load(data), bug6652)

    data = "\004\bu:\rDateTimeC\004\b[\bo:\rRational\a:\017@numeratorl+\bK\355B\024\003\000:\021" \
           "@denominatori\002\030\025i\000i\003\031\025#"
    assert_equal(DateTime.new(1993, 2, 24, 12, 34, 56), Marshal.load(data), bug6652)
  end
end
