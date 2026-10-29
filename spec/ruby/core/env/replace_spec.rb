require_relative '../../spec_helper'

describe "ENV.replace" do
  before :each do
    @orig = ENV.to_hash
    ENV.delete("foo")
  end

  after :each do
    ENV.replace(@orig)
  end

  it "replaces ENV with a Hash" do
    ENV.replace("foo" => "0", "bar" => "1").should.equal?(ENV)
    ENV.size.should == 2
    ENV["foo"].should == "0"
    ENV["bar"].should == "1"
  end

  platform_is_not :windows do
    it "keeps a variable with a non-ASCII name that is present in the Hash" do
      ENV["ENV_REPLACE_SPEC_\u00DCBER"] = "value"
      ENV.replace(ENV.to_hash)
      ENV["ENV_REPLACE_SPEC_\u00DCBER"].should == "value"
    end

    it "matches a variable name by its bytes regardless of the key's encoding" do
      key = "ENV_REPLACE_SPEC_\u00DCBER"
      ENV[key] = "value"
      ENV.replace(key.b => "binary")
      ENV[key].should == "binary"
      ENV.replace(key.encode(Encoding::ISO_8859_1) => "latin1")
      ENV[key].should == nil
      ENV[key.encode(Encoding::ISO_8859_1)].should == "latin1"
    end

    it "deletes a variable with a non-ASCII name that is absent from the Hash" do
      ENV["ENV_REPLACE_SPEC_\u00DCBER"] = "value"
      ENV.replace("foo" => "0")
      ENV["ENV_REPLACE_SPEC_\u00DCBER"].should == nil
    end
  end

  it "raises TypeError if the argument is not a Hash" do
    -> { ENV.replace(Object.new) }.should.raise(TypeError, "no implicit conversion of Object into Hash")
    ENV.to_hash.should == @orig
  end

  it "raises TypeError if a key is not a String" do
    -> { ENV.replace(Object.new => "0") }.should.raise(TypeError, "no implicit conversion of Object into String")
    ENV.to_hash.should == @orig
  end

  it "raises TypeError if a value is not a String" do
    -> { ENV.replace("foo" => Object.new) }.should.raise(TypeError, "no implicit conversion of Object into String")
    ENV.to_hash.should == @orig
  end

  it "raises Errno::EINVAL when the key contains the '=' character" do
    -> { ENV.replace("foo=" =>"bar") }.should.raise(Errno::EINVAL)
  end

  it "raises Errno::EINVAL when the key is an empty string" do
    -> { ENV.replace("" => "bar") }.should.raise(Errno::EINVAL)
  end

  it "applies good data preceding an error" do
    -> { ENV.replace("foo" => "1", Object.new => Object.new) }.should.raise(TypeError, "no implicit conversion of Object into String")
    ENV["foo"].should == "1"
  end

  it "does not accept good data following an error" do
    -> { ENV.replace(Object.new => Object.new, "foo" => "0") }.should.raise(TypeError, "no implicit conversion of Object into String")
    ENV.to_hash.should == @orig
  end
end
