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

  ruby_version_is ""..."3.0" do
    it "returns a Proc with #lambda? false" do
      pr = :to_s.to_proc
      pr.should_not.lambda?
    end

    it "produces a Proc with arity -1" do
      pr = :to_s.to_proc
      pr.arity.should == -1
    end

    it "produces a Proc that always returns [[:rest]] for #parameters" do
      pr = :to_s.to_proc
      pr.parameters.should == [[:rest]]
    end
  end

  ruby_version_is "3.0" do
    it "returns a Proc with #lambda? true" do
      pr = :to_s.to_proc
      pr.should.lambda?
    end

    it "produces a Proc with arity -2" do
      pr = :to_s.to_proc
      pr.arity.should == -2
    end

    it "produces a Proc that always returns [[:req], [:rest]] for #parameters" do
      pr = :to_s.to_proc
      pr.parameters.should == [[:req], [:rest]]
    end
  end

  it "raises an ArgumentError when calling #call on the Proc without receiver" do
    -> { :object_id.to_proc.call }.should raise_error(ArgumentError, "no receiver given")
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
