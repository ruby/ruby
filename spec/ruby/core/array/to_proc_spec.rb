require_relative '../../spec_helper'

describe "Array#to_proc" do
  ruby_version_is "3.2" do
    it "casts the array to proc" do
      [:itself].to_proc.should be_an_instance_of(Proc)
    end

    it "passes the arguments to the method" do
      [:insert, 1, 2, 3].to_proc.call([1, 4]).should == [1, 2, 3, 4]
    end

    it "casts String to Symbol" do
      ["itself"].to_proc.call('symbolized').should == 'symbolized'
    end

    it "raises an ArgumentError when the array is empty" do
      -> do
        [].to_proc.call
      end.should raise_error(ArgumentError)
    end

    it "raises a TypeError when the first element is not a symbol" do
      -> do
        [1].to_proc.call
      end.should raise_error(TypeError)
    end
  end
end
