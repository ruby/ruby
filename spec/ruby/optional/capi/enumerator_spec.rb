require_relative 'spec_helper'

load_extension("enumerator")

describe "C-API Enumerator function" do
  before :each do
    @s = CApiEnumeratorSpecs.new
  end

  describe "rb_enumeratorize" do
    before do
      @enumerable = [1, 2, 3]
    end

    it "constructs a new Enumerator for the given object, method and arguments" do
      enumerator = @s.rb_enumeratorize(@enumerable, :each, :arg1, :arg2)
      enumerator.class.should == Enumerator
    end

    it "enumerates the given object" do
      enumerator = @s.rb_enumeratorize(@enumerable, :each)
      enumerated = []
      enumerator.each { |i| enumerated << i }
      enumerated.should == @enumerable
    end

    it "uses the given method for enumeration" do
      enumerator = @s.rb_enumeratorize(@enumerable, :awesome_each)
      @enumerable.should_receive(:awesome_each)
      enumerator.each {}
    end

    it "passes the given arguments to the enumeration method" do
      enumerator = @s.rb_enumeratorize(@enumerable, :each, :arg1, :arg2)
      @enumerable.should_receive(:each).with(:arg1, :arg2)
      enumerator.each {}
    end
  end

  describe "rb_enumeratorize_with_size" do

    it "enumerates the given object" do
      enumerator = @s.rb_enumeratorize_with_size(@enumerable, :each)
      enumerated = []
      enumerator.each { |i| enumerated << i }
      enumerated.should == @enumerable
    end

    it "uses the given method for enumeration" do
      enumerator = @s.rb_enumeratorize_with_size(@enumerable, :awesome_each)
      @enumerable.should_receive(:awesome_each)
      enumerator.each {}
    end

    it "passes the given arguments to the enumeration method" do
      enumerator = @s.rb_enumeratorize_with_size(@enumerable, :each, :arg1, :arg2)
      @enumerable.should_receive(:each).with(:arg1, :arg2)
      enumerator.each {}
    end

    it "uses the size function to report the size" do
      enumerator = @s.rb_enumeratorize_with_size(@enumerable, :each, :arg1, :arg2)
      enumerator.size.should == 7
    end
  end
end
