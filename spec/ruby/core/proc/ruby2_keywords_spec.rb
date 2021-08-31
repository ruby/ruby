require_relative '../../spec_helper'

ruby_version_is "2.7" do
  describe "Proc#ruby2_keywords" do
    it "marks the final hash argument as keyword hash" do
      f = -> *a { a.last }
      f.ruby2_keywords

      last = f.call(1, 2, a: "a")
      Hash.ruby2_keywords_hash?(last).should == true
    end

    ruby_version_is "2.7" ... "3.0" do
      it "fixes delegation warnings when calling a method accepting keywords" do
        obj = Object.new
        def obj.foo(*a, **b) end

        f = -> *a { obj.foo(*a) }

        -> { f.call(1, 2, {a: "a"}) }.should complain(/Using the last argument as keyword parameters is deprecated/)
        f.ruby2_keywords
        -> { f.call(1, 2, {a: "a"}) }.should_not complain
      end

      it "fixes delegation warnings when calling a proc accepting keywords" do
        g = -> *a, **b { }
        f = -> *a { g.call(*a) }

        -> { f.call(1, 2, {a: "a"}) }.should complain(/Using the last argument as keyword parameters is deprecated/)
        f.ruby2_keywords
        -> { f.call(1, 2, {a: "a"}) }.should_not complain
      end
    end

    it "returns self" do
      f = -> *a { }
      f.ruby2_keywords.should equal f
    end

    it "prints warning when a proc does not accept argument splat" do
      f = -> a, b, c { }

      -> {
        f.ruby2_keywords
      }.should complain(/Skipping set of ruby2_keywords flag for/)
    end

    it "prints warning when a proc accepts keywords" do
      f = -> a:, b: { }

      -> {
        f.ruby2_keywords
      }.should complain(/Skipping set of ruby2_keywords flag for/)
    end

    it "prints warning when a proc accepts keyword splat" do
      f = -> **a { }

      -> {
        f.ruby2_keywords
      }.should complain(/Skipping set of ruby2_keywords flag for/)
    end
  end
end
