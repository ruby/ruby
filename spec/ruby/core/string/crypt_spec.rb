require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#crypt" do
  platform_is :openbsd do
    it "returns a cryptographic hash of self by applying the bcrypt algorithm with the specified salt" do
      "mypassword".crypt("$2a$04$0WVaz0pV3jzfZ5G5tpmHWu").should == "$2a$04$0WVaz0pV3jzfZ5G5tpmHWuBQGbkjzgtSc3gJbmdy0GAGMa45MFM2."

      # Only uses first 72 characters of string
      ("12345678"*9).crypt("$2a$04$0WVaz0pV3jzfZ5G5tpmHWu").should == "$2a$04$0WVaz0pV3jzfZ5G5tpmHWukj/ORBnsMjCGpST/zCJnAypc7eAbutK"
      ("12345678"*10).crypt("$2a$04$0WVaz0pV3jzfZ5G5tpmHWu").should == "$2a$04$0WVaz0pV3jzfZ5G5tpmHWukj/ORBnsMjCGpST/zCJnAypc7eAbutK"

      # Only uses first 29 characters of salt
      "mypassword".crypt("$2a$04$0WVaz0pV3jzfZ5G5tpmHWuB").should == "$2a$04$0WVaz0pV3jzfZ5G5tpmHWuBQGbkjzgtSc3gJbmdy0GAGMa45MFM2."
    end

    it "raises Errno::EINVAL when the salt is shorter than 29 characters" do
      -> { "mypassword".crypt("$2a$04$0WVaz0pV3jzfZ5G5tpmHW") }.should raise_error(Errno::EINVAL)
    end

    it "calls #to_str to converts the salt arg to a String" do
      obj = mock('$2a$04$0WVaz0pV3jzfZ5G5tpmHWu')
      obj.should_receive(:to_str).and_return("$2a$04$0WVaz0pV3jzfZ5G5tpmHWu")

      "mypassword".crypt(obj).should == "$2a$04$0WVaz0pV3jzfZ5G5tpmHWuBQGbkjzgtSc3gJbmdy0GAGMa45MFM2."
    end

    ruby_version_is ''...'2.7' do
      it "taints the result if either salt or self is tainted" do
        tainted_salt = "$2a$04$0WVaz0pV3jzfZ5G5tpmHWu"
        tainted_str = "mypassword"

        tainted_salt.taint
        tainted_str.taint

        "mypassword".crypt("$2a$04$0WVaz0pV3jzfZ5G5tpmHWu").tainted?.should == false
        tainted_str.crypt("$2a$04$0WVaz0pV3jzfZ5G5tpmHWu").tainted?.should == true
        "mypassword".crypt(tainted_salt).tainted?.should == true
        tainted_str.crypt(tainted_salt).tainted?.should == true
      end
    end

    it "doesn't return subclass instances" do
      StringSpecs::MyString.new("mypassword").crypt("$2a$04$0WVaz0pV3jzfZ5G5tpmHWu").should be_an_instance_of(String)
      "mypassword".crypt(StringSpecs::MyString.new("$2a$04$0WVaz0pV3jzfZ5G5tpmHWu")).should be_an_instance_of(String)
      StringSpecs::MyString.new("mypassword").crypt(StringSpecs::MyString.new("$2a$04$0WVaz0pV3jzfZ5G5tpmHWu")).should be_an_instance_of(String)
    end
  end

  platform_is_not :openbsd do
    # Note: MRI's documentation just says that the C stdlib function crypt() is
    # called.
    #
    # I'm not sure if crypt() is guaranteed to produce the same result across
    # different platforms. It seems that there is one standard UNIX implementation
    # of crypt(), but that alternative implementations are possible. See
    # http://www.unix.org.ua/orelly/networking/puis/ch08_06.htm
    it "returns a cryptographic hash of self by applying the UNIX crypt algorithm with the specified salt" do
      "".crypt("aa").should == "aaQSqAReePlq6"
      "nutmeg".crypt("Mi").should == "MiqkFWCm1fNJI"
      "ellen1".crypt("ri").should == "ri79kNd7V6.Sk"
      "Sharon".crypt("./").should == "./UY9Q7TvYJDg"
      "norahs".crypt("am").should == "amfIADT2iqjA."
      "norahs".crypt("7a").should == "7azfT5tIdyh0I"

      # Only uses first 8 chars of string
      "01234567".crypt("aa").should == "aa4c4gpuvCkSE"
      "012345678".crypt("aa").should == "aa4c4gpuvCkSE"
      "0123456789".crypt("aa").should == "aa4c4gpuvCkSE"

      # Only uses first 2 chars of salt
      "hello world".crypt("aa").should == "aayPz4hyPS1wI"
      "hello world".crypt("aab").should == "aayPz4hyPS1wI"
      "hello world".crypt("aabc").should == "aayPz4hyPS1wI"
    end

    it "raises an ArgumentError when the string contains NUL character" do
      -> { "poison\0null".crypt("aa") }.should raise_error(ArgumentError)
    end

    it "calls #to_str to converts the salt arg to a String" do
      obj = mock('aa')
      obj.should_receive(:to_str).and_return("aa")

      "".crypt(obj).should == "aaQSqAReePlq6"
    end

    ruby_version_is ''...'2.7' do
      it "taints the result if either salt or self is tainted" do
        tainted_salt = "aa"
        tainted_str = "hello"

        tainted_salt.taint
        tainted_str.taint

        "hello".crypt("aa").tainted?.should == false
        tainted_str.crypt("aa").tainted?.should == true
        "hello".crypt(tainted_salt).tainted?.should == true
        tainted_str.crypt(tainted_salt).tainted?.should == true
      end
    end

    it "doesn't return subclass instances" do
      StringSpecs::MyString.new("hello").crypt("aa").should be_an_instance_of(String)
      "hello".crypt(StringSpecs::MyString.new("aa")).should be_an_instance_of(String)
      StringSpecs::MyString.new("hello").crypt(StringSpecs::MyString.new("aa")).should be_an_instance_of(String)
    end

    it "raises an ArgumentError when the salt is shorter than two characters" do
      -> { "hello".crypt("")  }.should raise_error(ArgumentError)
      -> { "hello".crypt("f") }.should raise_error(ArgumentError)
      -> { "hello".crypt("\x00\x00") }.should raise_error(ArgumentError)
      -> { "hello".crypt("\x00a") }.should raise_error(ArgumentError)
      -> { "hello".crypt("a\x00") }.should raise_error(ArgumentError)
    end
  end

  it "raises a type error when the salt arg can't be converted to a string" do
    -> { "".crypt(5)         }.should raise_error(TypeError)
    -> { "".crypt(mock('x')) }.should raise_error(TypeError)
  end
end
