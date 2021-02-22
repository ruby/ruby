require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#lstrip" do
  it "returns a copy of self with leading whitespace removed" do
   "  hello  ".lstrip.should == "hello  "
   "  hello world  ".lstrip.should == "hello world  "
   "\n\r\t\n\v\r hello world  ".lstrip.should == "hello world  "
   "hello".lstrip.should == "hello"
  end

  ruby_version_is '3.1' do
    it "strips leading \\0" do
     "\x00hello".lstrip.should == "hello"
     "\000 \000hello\000 \000".lstrip.should == "hello\000 \000"
    end
  end

  ruby_version_is ''...'2.7' do
    it "taints the result when self is tainted" do
      "".taint.lstrip.should.tainted?
      "ok".taint.lstrip.should.tainted?
      "   ok".taint.lstrip.should.tainted?
    end
  end
end

describe "String#lstrip!" do
  it "modifies self in place and returns self" do
    a = "  hello  "
    a.lstrip!.should equal(a)
    a.should == "hello  "
  end

  ruby_version_is '3.1' do
    it "strips leading \\0" do
      a = "\000 \000hello\000 \000"
      a.lstrip!
      a.should == "hello\000 \000"
    end
  end

  it "returns nil if no modifications were made" do
    a = "hello"
    a.lstrip!.should == nil
    a.should == "hello"
  end

  it "raises a FrozenError on a frozen instance that is modified" do
    -> { "  hello  ".freeze.lstrip! }.should raise_error(FrozenError)
  end

  # see [ruby-core:23657]
  it "raises a FrozenError on a frozen instance that would not be modified" do
    -> { "hello".freeze.lstrip! }.should raise_error(FrozenError)
    -> { "".freeze.lstrip!      }.should raise_error(FrozenError)
  end
end
