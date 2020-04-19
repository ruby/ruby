require_relative "test_helper"

class BasicObjectTest < StdlibTest
  target BasicObject
  using hook.refinement

  def test_not
    BasicObject.new.!
  end

  def test_not_equal
    BasicObject.new.!=(1)
  end

  def test_equal
    BasicObject.new.==(1)
    BasicObject.new.equal?(1)
  end

  def test___id__
    BasicObject.new.__id__
  end

  def test___send__
    BasicObject.new.__send__(:__id__)
    BasicObject.new.__send__('__send__', :__id__)
  end

  def test_instance_eval
    BasicObject.new.instance_eval('__id__', 'filename', 1)
    BasicObject.new.instance_eval { |x| x }
  end

  def test_instance_exec
    BasicObject.new.instance_exec(1) { 10 }
    BasicObject.new.instance_exec(1,2,3) { 10 }
  end
end
