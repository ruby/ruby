require_relative '../../spec_helper'

describe "Symbol#to_proc" do
  it "returns a new Proc" do
    proc = :to_s.to_proc
    proc.should be_kind_of(Proc)
  end

  it "sends self to arguments passed when calling #call on the Proc" do
    obj = mock("Receiving #to_s")
    obj.should_receive(:to_s).and_return("Received #to_s")
    :to_s.to_proc.call(obj).should == "Received #to_s"
  end

  expected_arity = ruby_version_is("2.8") {-2} || -1
  it "produces a proc with arity #{expected_arity}" do
    pr = :to_s.to_proc
    pr.arity.should == expected_arity
  end

  it "raises an ArgumentError when calling #call on the Proc without receiver" do
    -> { :object_id.to_proc.call }.should raise_error(ArgumentError, "no receiver given")
  end

  expected_parameters = ruby_version_is("2.8") {[[:req], [:rest]]} || [[:rest]]
  it "produces a proc that always returns #{expected_parameters} for #parameters" do
    pr = :to_s.to_proc
    pr.parameters.should == expected_parameters
  end

  it "passes along the block passed to Proc#call" do
    klass = Class.new do
      def m
        yield
      end

      def to_proc
        :m.to_proc.call(self) { :value }
      end
    end
    klass.new.to_proc.should == :value
  end

  it "produces a proc with source location nil" do
    pr = :to_s.to_proc
    pr.source_location.should == nil
  end
end
