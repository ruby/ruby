require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Enumerable#to_set" do
  it "returns a new Set created from self" do
    [1, 2, 3].to_set.should == Set[1, 2, 3]
    {a: 1, b: 2}.to_set.should == Set[[:b, 2], [:a, 1]]
  end

  it "passes down passed blocks" do
    [1, 2, 3].to_set { |x| x * x }.should == Set[1, 4, 9]
  end

  ruby_version_is "3.5" do
    it "instantiates an object of provided as the first argument set class" do
      set = nil
      proc{set = [1, 2, 3].to_set(EnumerableSpecs::SetSubclass)}.should complain(/Enumerable#to_set/)
      set.should be_kind_of(EnumerableSpecs::SetSubclass)
      set.to_a.sort.should == [1, 2, 3]
    end
  end

  ruby_version_is ""..."3.5" do
    it "instantiates an object of provided as the first argument set class" do
      set = [1, 2, 3].to_set(EnumerableSpecs::SetSubclass)
      set.should be_kind_of(EnumerableSpecs::SetSubclass)
      set.to_a.sort.should == [1, 2, 3]
    end
  end

  it "does not need explicit `require 'set'`" do
    output = ruby_exe(<<~RUBY, options: '--disable-gems', args: '2>&1')
      puts [1, 2, 3].to_set.to_a.inspect
    RUBY

    output.chomp.should == "[1, 2, 3]"
  end
end
