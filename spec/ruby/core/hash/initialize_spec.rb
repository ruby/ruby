require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Hash#initialize" do
  it "is private" do
    Hash.should have_private_instance_method("initialize")
  end

  it "can be used to reset default_proc" do
    h = { "foo" => 1, "bar" => 2 }
    h.default_proc.should == nil
    h.send(:initialize) { |_, k| k * 2 }
    h.default_proc.should_not == nil
    h["a"].should == "aa"
  end

  it "can be used to reset the default value" do
    h = {}
    h.default = 42
    h.default.should == 42
    h.send(:initialize, 1)
    h.default.should == 1
    h.send(:initialize)
    h.default.should == nil
  end

  it "receives the arguments passed to Hash#new" do
    HashSpecs::NewHash.new(:one, :two)[0].should == :one
    HashSpecs::NewHash.new(:one, :two)[1].should == :two
  end

  it "does not change the storage, only the default value or proc" do
    h = HashSpecs::SubHashSettingInInitialize.new
    h.to_a.should == [[:foo, :bar]]

    h = HashSpecs::SubHashSettingInInitialize.new(:default)
    h.to_a.should == [[:foo, :bar]]

    h = HashSpecs::SubHashSettingInInitialize.new { :default_block }
    h.to_a.should == [[:foo, :bar]]
  end

  it "returns self" do
    h = Hash.new
    h.send(:initialize).should equal(h)
  end

  it "raises a #{frozen_error_class} if called on a frozen instance" do
    block = -> { HashSpecs.frozen_hash.instance_eval { initialize() }}
    block.should raise_error(frozen_error_class)

    block = -> { HashSpecs.frozen_hash.instance_eval { initialize(nil) }  }
    block.should raise_error(frozen_error_class)

    block = -> { HashSpecs.frozen_hash.instance_eval { initialize(5) }    }
    block.should raise_error(frozen_error_class)

    block = -> { HashSpecs.frozen_hash.instance_eval { initialize { 5 } } }
    block.should raise_error(frozen_error_class)
  end
end
