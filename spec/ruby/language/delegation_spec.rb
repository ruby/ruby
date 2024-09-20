require_relative '../spec_helper'
require_relative 'fixtures/delegation'

describe "delegation with def(...)" do
  it "delegates rest and kwargs" do
    a = Class.new(DelegationSpecs::Target)
    a.class_eval(<<-RUBY)
      def delegate(...)
        target(...)
      end
    RUBY

    a.new.delegate(1, b: 2).should == [[1], {b: 2}]
  end

  it "delegates block" do
    a = Class.new(DelegationSpecs::Target)
    a.class_eval(<<-RUBY)
      def delegate_block(...)
        target_block(...)
      end
    RUBY

    a.new.delegate_block(1, b: 2) { |x| x }.should == [{b: 2}, [1]]
  end

  it "parses as open endless Range when brackets are omitted" do
    a = Class.new(DelegationSpecs::Target)
    suppress_warning do
      a.class_eval(<<-RUBY)
        def delegate(...)
          target ...
        end
      RUBY
    end

    a.new.delegate(1, b: 2).should == Range.new([[], {}], nil, true)
  end
end

describe "delegation with def(x, ...)" do
  it "delegates rest and kwargs" do
    a = Class.new(DelegationSpecs::Target)
    a.class_eval(<<-RUBY)
      def delegate(x, ...)
        target(...)
      end
    RUBY

    a.new.delegate(0, 1, b: 2).should == [[1], {b: 2}]
  end

  it "delegates block" do
    a = Class.new(DelegationSpecs::Target)
    a.class_eval(<<-RUBY)
      def delegate_block(x, ...)
        target_block(...)
      end
    RUBY

    a.new.delegate_block(0, 1, b: 2) { |x| x }.should == [{b: 2}, [1]]
  end
end

ruby_version_is "3.2" do
  describe "delegation with def(*)" do
    it "delegates rest" do
      a = Class.new(DelegationSpecs::Target)
      a.class_eval(<<-RUBY)
      def delegate(*)
        target(*)
      end
    RUBY

      a.new.delegate(0, 1).should == [[0, 1], {}]
    end
  end
end

ruby_version_is "3.2" do
  describe "delegation with def(**)" do
    it "delegates kwargs" do
      a = Class.new(DelegationSpecs::Target)
      a.class_eval(<<-RUBY)
      def delegate(**)
        target(**)
      end
    RUBY

      a.new.delegate(a: 1) { |x| x }.should == [[], {a: 1}]
    end
  end
end
