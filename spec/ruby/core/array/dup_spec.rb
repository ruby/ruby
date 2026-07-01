require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/clone'

describe "Array#dup" do
  it_behaves_like :array_clone, :dup # FIX: no, clone and dup are not alike

  it "does not copy frozen status from the original" do
    a = [1, 2, 3, 4]
    b = [1, 2, 3, 4]
    a.freeze
    aa = a.dup
    bb = b.dup

    aa.frozen?.should == false
    bb.frozen?.should == false
  end

  it "does not copy singleton methods" do
    a = [1, 2, 3, 4]
    b = [1, 2, 3, 4]
    def a.a_singleton_method; end
    aa = a.dup
    bb = b.dup

    a.respond_to?(:a_singleton_method).should == true
    b.respond_to?(:a_singleton_method).should == false
    aa.respond_to?(:a_singleton_method).should == false
    bb.respond_to?(:a_singleton_method).should == false
  end
end
