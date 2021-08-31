require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "2.7" do
  describe "Hash.ruby2_keywords_hash?" do
    it "returns false if the Hash is not a keywords Hash" do
      Hash.ruby2_keywords_hash?({}).should == false
    end

    it "returns true if the Hash is a keywords Hash marked by Module#ruby2_keywords" do
      obj = Class.new {
        ruby2_keywords def m(*args)
          args.last
        end
      }.new
      Hash.ruby2_keywords_hash?(obj.m(a: 1)).should == true
    end

    it "raises TypeError for non-Hash" do
      -> { Hash.ruby2_keywords_hash?(nil) }.should raise_error(TypeError)
    end
  end

  describe "Hash.ruby2_keywords_hash" do
    it "returns a copy of a Hash and marks the copy as a keywords Hash" do
      h = {a: 1}.freeze
      kw = Hash.ruby2_keywords_hash(h)
      Hash.ruby2_keywords_hash?(h).should == false
      Hash.ruby2_keywords_hash?(kw).should == true
      kw.should == h
    end

    it "returns an instance of the subclass if called on an instance of a subclass of Hash" do
      h = HashSpecs::MyHash.new
      h[:a] = 1
      kw = Hash.ruby2_keywords_hash(h)
      kw.class.should == HashSpecs::MyHash
      Hash.ruby2_keywords_hash?(h).should == false
      Hash.ruby2_keywords_hash?(kw).should == true
      kw.should == h
    end

    it "raises TypeError for non-Hash" do
      -> { Hash.ruby2_keywords_hash(nil) }.should raise_error(TypeError)
    end
  end
end
