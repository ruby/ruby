require_relative 'spec_helper'
require_relative 'shared/to_hash'

describe "ENV.to_h" do
  it_behaves_like :env_to_hash, :to_h

  ruby_version_is "2.6" do
    context "with block" do
      before do
        @orig_hash = ENV.to_hash
      end

      after do
        ENV.replace @orig_hash
      end

      it "converts [key, value] pairs returned by the block to a hash" do
        ENV.replace("a" => "b", "c" => "d")
        ENV.to_h { |k, v| [k, v.upcase] }.should == { 'a' => "B", 'c' => "D" }
      end

      it "does not require the array elements to be strings" do
        ENV.replace("a" => "b", "c" => "d")
        ENV.to_h { |k, v| [k.to_sym, v.to_sym] }.should == { :a => :b, :c => :d }
      end

      it "raises ArgumentError if block returns longer or shorter array" do
        -> do
          ENV.to_h { |k, v| [k, v.upcase, 1] }
        end.should raise_error(ArgumentError, /element has wrong array length/)

        -> do
          ENV.to_h { |k, v| [k] }
        end.should raise_error(ArgumentError, /element has wrong array length/)
      end

      it "raises TypeError if block returns something other than Array" do
        -> do
          ENV.to_h { |k, v| "not-array" }
        end.should raise_error(TypeError, /wrong element type String/)
      end

      it "coerces returned pair to Array with #to_ary" do
        x = mock('x')
        x.stub!(:to_ary).and_return([:b, 'b'])

        ENV.to_h { |k| x }.should == { :b => 'b' }
      end

      it "does not coerce returned pair to Array with #to_a" do
        x = mock('x')
        x.stub!(:to_a).and_return([:b, 'b'])

        -> do
          ENV.to_h { |k| x }
        end.should raise_error(TypeError, /wrong element type MockObject/)
      end
    end
  end
end
