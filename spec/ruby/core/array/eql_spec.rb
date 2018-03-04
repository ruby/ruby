require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/eql'

describe "Array#eql?" do
  it_behaves_like :array_eql, :eql?

  it "returns false if any corresponding elements are not #eql?" do
    [1, 2, 3, 4].send(@method, [1, 2, 3, 4.0]).should be_false
  end

  it "returns false if other is not a kind of Array" do
    obj = mock("array eql?")
    obj.should_not_receive(:to_ary)
    obj.should_not_receive(@method)

    [1, 2, 3].send(@method, obj).should be_false
  end
end
