require_relative '../../spec_helper'
require_relative '../../shared/kernel/equal'

describe "BasicObject#==" do
  it "is a public instance method" do
    BasicObject.public_instance_methods(false).should.include?(:==)
  end

  it_behaves_like :object_equal, :==

  it "is unaffected by overriding __id__" do
    o1 = mock("object")
    o2 = mock("object")
    suppress_warning {
      def o1.__id__; 10; end
      def o2.__id__; 10; end
    }
    (o1 == o2).should == false
  end

  it "is unaffected by overriding object_id" do
    o1 = mock("object")
    o1.stub!(:object_id).and_return(10)
    o2 = mock("object")
    o2.stub!(:object_id).and_return(10)
    (o1 == o2).should == false
  end

  it "is unaffected by overriding equal?" do
    # different objects, overriding equal? to return true
    o1 = mock("object")
    o1.stub!(:equal?).and_return(true)
    o2 = mock("object")
    (o1 == o2).should == false

    # same objects, overriding equal? to return false
    o3 = mock("object")
    o3.stub!(:equal?).and_return(false)
    (o3 == o3).should == true
  end

  it "is unaffected by overriding eql?" do
    # different objects, overriding eql? to return true
    o1 = mock("object")
    o1.stub!(:eql?).and_return(true)
    o2 = mock("object")
    (o1 == o2).should == false

    # same objects, overriding eql? to return false
    o3 = mock("object")
    o3.stub!(:eql?).and_return(false)
    (o3 == o3).should == true
  end
end
