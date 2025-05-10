require_relative '../../spec_helper'

ruby_version_is "3.5" do
  describe "ObjectSpace._id2ref" do
    it "is deprecated" do
      id = nil.object_id
      -> {
        ObjectSpace._id2ref(id)
      }.should complain(/warning: ObjectSpace\._id2ref is deprecated/)
    end
  end
end

ruby_version_is ""..."3.5" do
  describe "ObjectSpace._id2ref" do
    it "converts an object id to a reference to the object" do
      s = "I am a string"
      r = ObjectSpace._id2ref(s.object_id)
      r.should == s
    end

    it "retrieves true by object_id" do
      ObjectSpace._id2ref(true.object_id).should == true
    end

    it "retrieves false by object_id" do
      ObjectSpace._id2ref(false.object_id).should == false
    end

    it "retrieves nil by object_id" do
      ObjectSpace._id2ref(nil.object_id).should == nil
    end

    it "retrieves a small Integer by object_id" do
      ObjectSpace._id2ref(1.object_id).should == 1
      ObjectSpace._id2ref((-42).object_id).should == -42
    end

    it "retrieves a large Integer by object_id" do
      obj = 1 << 88
      ObjectSpace._id2ref(obj.object_id).should.equal?(obj)
    end

    it "retrieves a Symbol by object_id" do
      ObjectSpace._id2ref(:sym.object_id).should.equal?(:sym)
    end

    it "retrieves a String by object_id" do
      obj = "str"
      ObjectSpace._id2ref(obj.object_id).should.equal?(obj)
    end

    it "retrieves a frozen literal String by object_id" do
      ObjectSpace._id2ref("frozen string literal _id2ref".freeze.object_id).should.equal?("frozen string literal _id2ref".freeze)
    end

    it "retrieves an Encoding by object_id" do
      ObjectSpace._id2ref(Encoding::UTF_8.object_id).should.equal?(Encoding::UTF_8)
    end

    it 'raises RangeError when an object could not be found' do
      proc { ObjectSpace._id2ref(1 << 60) }.should raise_error(RangeError)
    end
  end
end
