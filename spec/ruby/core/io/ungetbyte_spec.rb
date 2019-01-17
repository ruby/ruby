require_relative '../../spec_helper'

describe "IO#ungetbyte" do
  before :each do
    @name = tmp("io_ungetbyte")
    touch(@name) { |f| f.write "a" }
    @io = new_io @name, "r"
  end

  after :each do
    @io.close unless @io.closed?
    rm_r @name
  end

  it "does nothing when passed nil" do
    @io.ungetbyte(nil).should be_nil
    @io.getbyte.should == 97
  end

  it "puts back each byte in a String argument" do
    @io.ungetbyte("cat").should be_nil
    @io.getbyte.should == 99
    @io.getbyte.should == 97
    @io.getbyte.should == 116
    @io.getbyte.should == 97
  end

  it "calls #to_str to convert the argument" do
    str = mock("io ungetbyte")
    str.should_receive(:to_str).and_return("dog")

    @io.ungetbyte(str).should be_nil
    @io.getbyte.should == 100
    @io.getbyte.should == 111
    @io.getbyte.should == 103
    @io.getbyte.should == 97
  end

  ruby_version_is ''...'2.6' do
    it "puts back one byte for a Fixnum argument..." do
      @io.ungetbyte(4095).should be_nil
      @io.getbyte.should == 255
    end

    it "... but not for Bignum argument (eh?)" do
      lambda {
        @io.ungetbyte(0x4f7574206f6620636861722072616e6765)
      }.should raise_error(TypeError)
    end
  end

  ruby_version_is '2.6'...'2.7' do
    it "is an RangeError if the integer is not in 8bit" do
      for i in [4095, 0x4f7574206f6620636861722072616e6765] do
        lambda { @io.ungetbyte(i) }.should raise_error(RangeError)
      end
    end
  end

  ruby_version_is '2.7' do
    it "never raises RangeError" do
      for i in [4095, 0x4f7574206f6620636861722072616e6765] do
        lambda { @io.ungetbyte(i) }.should_not raise_error
      end
    end
  end

  it "raises an IOError if the IO is closed" do
    @io.close
    lambda { @io.ungetbyte(42) }.should raise_error(IOError)
  end
end
