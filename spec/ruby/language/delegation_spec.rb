require_relative '../spec_helper'
require_relative 'fixtures/delegation'

# Forwarding anonymous parameters
describe "delegation with def(...)" do
  it "delegates rest and kwargs" do
    a = Class.new(DelegationSpecs::Target)
    a.class_eval(<<-RUBY)
      def delegate(...)
        target(...)
      end
    RUBY

    a.new.delegate(1, b: 2).should == [[1], {b: 2}, nil]
  end

  it "delegates a block literal" do
    a = Class.new(DelegationSpecs::Target)
    a.class_eval(<<-RUBY)
      def delegate_block(...)
        target_block(...)
      end
    RUBY

    a.new.delegate_block(1, b: 2) { |x| x }.should == [{b: 2}, [1]]
  end

  it "delegates a block argument" do
    a = Class.new(DelegationSpecs::Target)
    a.class_eval(<<-RUBY)
      def delegate(...)
        target(...)
      end
    RUBY

    block = proc {}
    a.new.delegate(1, b: 2, &block).should == [[1], {b: 2}, block]
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

    a.new.delegate(1, b: 2).should == Range.new([[], {}, nil], nil, true)
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

    a.new.delegate(0, 1, b: 2).should == [[1], {b: 2}, nil]
  end

  it "delegates a block literal" do
    a = Class.new(DelegationSpecs::Target)
    a.class_eval(<<-RUBY)
      def delegate_block(x, ...)
        target_block(...)
      end
    RUBY

    a.new.delegate_block(0, 1, b: 2) { |x| x }.should == [{b: 2}, [1]]
  end

  it "delegates a block argument" do
    a = Class.new(DelegationSpecs::Target)
    a.class_eval(<<-RUBY)
      def delegate(...)
        target(...)
      end
    RUBY

    block = proc {}
    a.new.delegate(1, b: 2, &block).should == [[1], {b: 2}, block]
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

      a.new.delegate(0, 1).should == [[0, 1], {}, nil]
    end

    ruby_version_is "3.3" do
      context "within a block that accepts anonymous rest within a method that accepts anonymous rest" do
        it "does not allow delegating rest" do
          -> {
            eval "def m(*); proc { |*| n(*) } end"
          }.should raise_error(SyntaxError, /anonymous rest parameter is also used within block/)
        end
      end
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

      a.new.delegate(a: 1) { |x| x }.should == [[], {a: 1}, nil]
    end

    ruby_version_is "3.3" do
      context "within a block that accepts anonymous kwargs within a method that accepts anonymous kwargs" do
        it "does not allow delegating kwargs" do
          -> {
            eval "def m(**); proc { |**| n(**) } end"
          }.should raise_error(SyntaxError, /anonymous keyword rest parameter is also used within block/)
        end
      end
    end
  end
end

ruby_version_is "3.1" do
  describe "delegation with def(&)" do
    it "delegates an anonymous block parameter" do
      a = Class.new(DelegationSpecs::Target)
      a.class_eval(<<-RUBY)
      def delegate(&)
        target(&)
      end
      RUBY

      block = proc {}
      a.new.delegate(&block).should == [[], {}, block]
    end

    ruby_version_is "3.3" do
      context "within a block that accepts anonymous block within a method that accepts anonymous block" do
        it "does not allow delegating a block" do
          -> {
            eval "def m(&); proc { |&| n(&) } end"
          }.should raise_error(SyntaxError, /anonymous block parameter is also used within block/)
        end
      end
    end
  end
end
