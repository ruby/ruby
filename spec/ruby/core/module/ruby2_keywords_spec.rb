require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "2.7" do
  describe "Module#ruby2_keywords" do
    it "marks the final hash argument as keyword hash" do
      obj = Object.new

      obj.singleton_class.class_exec do
        def foo(*a) a.last end
        ruby2_keywords :foo
      end

      last = obj.foo(1, 2, a: "a")
      Hash.ruby2_keywords_hash?(last).should == true
    end

    ruby_version_is "2.7" ... "3.0" do
      it "fixes delegation warnings when calling a method accepting keywords" do
        obj = Object.new

        obj.singleton_class.class_exec do
          def foo(*a) bar(*a) end
          def bar(*a, **b) end
        end

        -> { obj.foo(1, 2, {a: "a"}) }.should complain(/Using the last argument as keyword parameters is deprecated/)

        obj.singleton_class.class_exec do
          ruby2_keywords :foo
        end

        -> { obj.foo(1, 2, {a: "a"}) }.should_not complain
      end
    end

    it "returns nil" do
      obj = Object.new

      obj.singleton_class.class_exec do
        def foo(*a) end

        ruby2_keywords(:foo).should == nil
      end
    end

    it "raises NameError when passed not existing method name" do
      obj = Object.new

      -> {
        obj.singleton_class.class_exec do
          ruby2_keywords :not_existing
        end
      }.should raise_error(NameError, /undefined method `not_existing'/)
    end

    it "acceps String as well" do
      obj = Object.new

      obj.singleton_class.class_exec do
        def foo(*a) a.last end
        ruby2_keywords "foo"
      end

      last = obj.foo(1, 2, a: "a")
      Hash.ruby2_keywords_hash?(last).should == true
    end

    it "raises TypeError when passed not Symbol or String" do
      obj = Object.new

      -> {
        obj.singleton_class.class_exec do
          ruby2_keywords Object.new
        end
      }.should raise_error(TypeError, /is not a symbol nor a string/)
    end

    it "prints warning when a method does not accept argument splat" do
      obj = Object.new
      def obj.foo(a, b, c) end

      -> {
        obj.singleton_class.class_exec do
          ruby2_keywords :foo
        end
      }.should complain(/Skipping set of ruby2_keywords flag for/)
    end

    it "prints warning when a method accepts keywords" do
      obj = Object.new
      def obj.foo(a:, b:) end

      -> {
        obj.singleton_class.class_exec do
          ruby2_keywords :foo
        end
      }.should complain(/Skipping set of ruby2_keywords flag for/)
    end

    it "prints warning when a method accepts keyword splat" do
      obj = Object.new
      def obj.foo(**a) end

      -> {
        obj.singleton_class.class_exec do
          ruby2_keywords :foo
        end
      }.should complain(/Skipping set of ruby2_keywords flag for/)
    end
  end
end
