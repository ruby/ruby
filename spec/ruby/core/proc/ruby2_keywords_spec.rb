require_relative '../../spec_helper'

describe "Proc#ruby2_keywords" do
  it "marks the final hash argument as keyword hash" do
    f = -> *a { a.last }
    f.ruby2_keywords

    last = f.call(1, 2, a: "a")
    Hash.ruby2_keywords_hash?(last).should == true
  end

  it "applies to the underlying method and applies across duplication" do
    f1 = -> *a { a.last }
    f1.ruby2_keywords
    f2 = f1.dup

    Hash.ruby2_keywords_hash?(f1.call(1, 2, a: "a")).should == true
    Hash.ruby2_keywords_hash?(f2.call(1, 2, a: "a")).should == true

    f3 = -> *a { a.last }
    f4 = f3.dup
    f3.ruby2_keywords

    Hash.ruby2_keywords_hash?(f3.call(1, 2, a: "a")).should == true
    Hash.ruby2_keywords_hash?(f4.call(1, 2, a: "a")).should == true
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
