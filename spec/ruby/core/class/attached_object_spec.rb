require_relative '../../spec_helper'

ruby_version_is '3.2' do
  describe "Class#attached_object" do
    it "returns the object that is attached to a singleton class" do
      a = Class.new

      a_obj = a.new
      a_obj.singleton_class.attached_object.should == a_obj
    end

    it "returns the class object that is attached to a class's singleton class" do
      a = Class.new
      singleton_class = (class << a; self; end)

      singleton_class.attached_object.should == a
    end

    it "raises TypeError if the class is not a singleton class" do
      a = Class.new

      -> { a.attached_object }.should raise_error(TypeError, /is not a singleton class/)
    end

    it "raises TypeError for special singleton classes" do
      -> { nil.singleton_class.attached_object }.should raise_error(TypeError, /[`']NilClass' is not a singleton class/)
      -> { true.singleton_class.attached_object }.should raise_error(TypeError, /[`']TrueClass' is not a singleton class/)
      -> { false.singleton_class.attached_object }.should raise_error(TypeError, /[`']FalseClass' is not a singleton class/)
    end
  end
end
