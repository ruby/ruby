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

    it "makes a copy of the hash and only marks the copy as keyword hash" do
      obj = Object.new
      obj.singleton_class.class_exec do
        def regular(*args)
          args.last
        end

        ruby2_keywords def foo(*args)
          args.last
        end
      end

      h = {a: 1}
      ruby_version_is "3.0" do
        obj.regular(**h).should.equal?(h)
      end

      last = obj.foo(**h)
      Hash.ruby2_keywords_hash?(last).should == true
      Hash.ruby2_keywords_hash?(h).should == false

      last2 = obj.foo(**last) # last is already marked
      Hash.ruby2_keywords_hash?(last2).should == true
      Hash.ruby2_keywords_hash?(last).should == true
      last2.should_not.equal?(last)
      Hash.ruby2_keywords_hash?(h).should == false
    end

    it "makes a copy and unmark at the call site when calling with marked *args" do
      obj = Object.new
      obj.singleton_class.class_exec do
        ruby2_keywords def foo(*args)
          args
        end

        def single(arg)
          arg
        end

        def splat(*args)
          args.last
        end

        def kwargs(**kw)
          kw
        end
      end

      h = { a: 1 }
      args = obj.foo(**h)
      marked = args.last
      Hash.ruby2_keywords_hash?(marked).should == true

      after_usage = obj.single(*args)
      after_usage.should == h
      after_usage.should_not.equal?(h)
      after_usage.should_not.equal?(marked)
      Hash.ruby2_keywords_hash?(after_usage).should == false
      Hash.ruby2_keywords_hash?(marked).should == true

      after_usage = obj.splat(*args)
      after_usage.should == h
      after_usage.should_not.equal?(h)
      after_usage.should_not.equal?(marked)
      ruby_bug "#18625", ""..."3.3" do # might be fixed in 3.2
        Hash.ruby2_keywords_hash?(after_usage).should == false
      end
      Hash.ruby2_keywords_hash?(marked).should == true

      after_usage = obj.kwargs(*args)
      after_usage.should == h
      after_usage.should_not.equal?(h)
      after_usage.should_not.equal?(marked)
      Hash.ruby2_keywords_hash?(after_usage).should == false
      Hash.ruby2_keywords_hash?(marked).should == true
    end

    it "applies to the underlying method and applies across aliasing" do
      obj = Object.new

      obj.singleton_class.class_exec do
        def foo(*a) a.last end
        alias_method :bar, :foo
        ruby2_keywords :foo

        def baz(*a) a.last end
        ruby2_keywords :baz
        alias_method :bob, :baz
      end

      last = obj.foo(1, 2, a: "a")
      Hash.ruby2_keywords_hash?(last).should == true

      last = obj.bar(1, 2, a: "a")
      Hash.ruby2_keywords_hash?(last).should == true

      last = obj.baz(1, 2, a: "a")
      Hash.ruby2_keywords_hash?(last).should == true

      last = obj.bob(1, 2, a: "a")
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

    it "accepts String as well" do
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
