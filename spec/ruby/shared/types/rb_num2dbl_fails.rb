#
# Shared tests for rb_num2dbl related conversion failures.
#
# Usage example:
#   it_behaves_like :rb_num2dbl_fails, nil, -> v { o = A.new; o.foo(v) }
#

describe :rb_num2dbl_fails, shared: true do
  it "fails if string is provided" do
    -> { @object.call("123") }.should raise_consistent_error(TypeError, "no implicit conversion of String into Float")
  end

  it "fails if boolean is provided" do
    -> { @object.call(true) }.should raise_consistent_error(TypeError, "no implicit conversion of true into Float")
    -> { @object.call(false) }.should raise_consistent_error(TypeError, "no implicit conversion of false into Float")
  end
end
