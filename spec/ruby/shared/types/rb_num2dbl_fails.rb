#
# Shared tests for rb_num2dbl related conversion failures.
#
# Usage example:
#   it_behaves_like :rb_num2dbl_fails, nil, -> v { o = A.new; o.foo(v) }
#

describe :rb_num2dbl_fails, shared: true do
  it "fails if string is provided" do
    -> { @object.call("123") }.should raise_error(TypeError, "no implicit conversion to float from string")
  end

  it "fails if boolean is provided" do
    -> { @object.call(true) }.should raise_error(TypeError, "no implicit conversion to float from true")
    -> { @object.call(false) }.should raise_error(TypeError, "no implicit conversion to float from false")
  end
end
