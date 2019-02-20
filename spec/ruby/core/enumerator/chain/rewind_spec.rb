require_relative '../../../spec_helper'

ruby_version_is "2.6" do
  describe "Enumerator::Chain#rewind" do
    before(:each) do
      @obj = mock('obj')
      @obj.should_receive(:each).any_number_of_times.and_yield
      @second = mock('obj')
      @second.should_receive(:each).any_number_of_times.and_yield
      @enum = Enumerator::Chain.new(@obj, @second)
    end

    it "returns self" do
      @enum.rewind.should equal @enum
    end

    it "does nothing if receiver has not been iterated" do
      @obj.should_not_receive(:rewind)
      @obj.respond_to?(:rewind).should == true # sanity check
      @enum.rewind
    end

    it "does nothing on objects that don't respond_to rewind" do
      @obj.respond_to?(:rewind).should == false # sanity check
      @enum.each {}
      @enum.rewind
    end

    it "calls_rewind its objects" do
      @obj.should_receive(:rewind)
      @enum.each {}
      @enum.rewind
    end

    it "calls_rewind in reverse order" do
      @obj.should_not_receive(:rewind)
      @second.should_receive(:rewind).and_raise(RuntimeError)
      @enum.each {}
      lambda { @enum.rewind }.should raise_error(RuntimeError)
    end

    it "calls rewind only for objects that have actually been iterated on" do
      @obj = mock('obj')
      @obj.should_receive(:each).any_number_of_times.and_raise(RuntimeError)
      @enum = Enumerator::Chain.new(@obj, @second)

      @obj.should_receive(:rewind)
      @second.should_not_receive(:rewind)
      lambda { @enum.each {} }.should raise_error(RuntimeError)
      @enum.rewind
    end
  end
end
