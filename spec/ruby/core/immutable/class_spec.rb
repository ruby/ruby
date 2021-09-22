require_relative '../../spec_helper'

ruby_version_is "3.3" do
  describe Immutable do
    it "can be applied to a class" do
      test_class = Class.new
      test_class.extend(Immutable)

      instance = test_class.new

      instance.should be_an_instance_of(test_class)
      instance.should.frozen?
      instance.should.immutable?
    end

    it "is still immutable after dup" do
      test_class = Class.new
      test_class.extend(Immutable)

      instance = test_class.new.dup

      instance.should.frozen?
      instance.should.immutable?
      instance.should.equal?(instance.dup)
    end

    it "is still immutable after clone" do
      test_class = Class.new
      test_class.extend(Immutable)

      instance = test_class.new.clone

      instance.should.frozen?
      instance.should.immutable?
      instance.should.equal?(instance.clone)
    end

    it "applies to sub-classes" do
      base_class = Class.new
      base_class.extend(Immutable)

      test_class = Class.new(base_class)

      instance = test_class.new

      instance.should be_an_instance_of(test_class)
      instance.should.frozen?
      instance.should.immutable?
    end

    it "doesn't affect allocate" do
      test_class = Class.new
      test_class.extend(Immutable)

      instance = test_class.allocate
      instance.send(:initialize)

      instance.should_not.frozen?
      instance.should_not.immutable?

      Immutable(instance)

      instance.should be_an_instance_of(test_class)
      instance.should.frozen?
      instance.should.immutable?
    end
  end
end
