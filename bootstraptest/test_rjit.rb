# VM_CALL_OPT_SEND + VM_METHOD_TYPE_ATTRSET
assert_equal '1', %q{
  class Foo
    attr_writer :foo

    def bar
      send(:foo=, 1)
    end
  end

  Foo.new.bar
}

# VM_CALL_OPT_SEND + OPTIMIZED_METHOD_TYPE_CALL
assert_equal 'foo', %q{
  def bar(&foo)
    foo.send(:call)
  end

  bar { :foo }
}

# VM_CALL_OPT_SEND + OPTIMIZED_METHOD_TYPE_STRUCT_AREF
assert_equal 'bar', %q{
  def bar(foo)
    foo.send(:bar)
  end

  bar(Struct.new(:bar).new(:bar))
}

# AND with offset  DISP32
assert_equal '2', %q{
  def foo
    a = 6;
    b = {a: 1, b: 1, c: 1, d: 1, e: 1,  f: 1, g: 1, h: a&3}
    b[:h]
  end

  foo
}

# OR with offset DISP32
assert_equal '6', %q{
  def foo
    a = 4;
    b = {a: 1, b: 1, c: 1, d: 1, e: 1,  f: 1, g: 1, h: a|2}
    b[:h]
  end

  foo
}

# kwargs default w/ checkkeyword + locals (which shouldn't overwrite unspecified_bits)
assert_equal '1', %q{
  def foo(bar: 1.to_s)
    _ = 1
    bar
  end

  def entry
    foo
  end

  entry
}

# Updating local type in Context
assert_normal_exit %q{
  def foo(flag, object)
    klass = if flag
      object
    end
    klass ||= object
    return klass.new
  end

  foo(false, Object)
  foo(true, Object)
}
