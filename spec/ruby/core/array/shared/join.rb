require_relative '../fixtures/classes'
require_relative '../fixtures/encoded_strings'

describe :array_join_with_string_separator, shared: true do
  it "returns a string formed by concatenating each element.to_str separated by separator" do
    obj = mock('foo')
    obj.should_receive(:to_str).and_return("foo")
    [1, 2, 3, 4, obj].send(@method, ' | ').should == '1 | 2 | 3 | 4 | foo'
  end

  it "uses the same separator with nested arrays" do
    [1, [2, [3, 4], 5], 6].send(@method, ":").should == "1:2:3:4:5:6"
    [1, [2, ArraySpecs::MyArray[3, 4], 5], 6].send(@method, ":").should == "1:2:3:4:5:6"
  end
end
