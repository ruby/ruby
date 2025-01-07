require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/store'

describe "Hash#store" do
  it_behaves_like :hash_store, :store

  ruby_version_is "3.4" do
    context "when a block is given" do
      it "yields nil if no default value is set" do
        h = {}
        h.store("foo") do |v|
          v.should == nil
          nil
        end
      end

      it "yields the default value if set" do
        h = {}
        h.default = 100
        h.store("foo") do |v|
          v.should == 100
          nil
        end
      end

      it "yields nil if a default proc is set" do
        h = Hash.new {|h, k| h[k] = 0}
        h.store("foo") do |v|
          v.should == nil
          nil
        end

        h = {}
        h.default = 100
        h.default_proc = lambda {|h, k| h[k] = 0}
        h.store("foo") do |v|
          v.should == nil
          nil
        end
      end

      it "associates the key with the value returned by the block" do
        h = {}
        h.store("foo") do |v|
          "bar"
        end
        h["foo"].should == "bar"

        h.store("foo") do |v|
          "baz"
        end
        h["foo"].should == "baz"
      end

      it "raises ArgumentError if a block and an explicit value are passed" do
        -> { {}.store("foo", "bar") { "baz" } }.should raise_error(ArgumentError)
      end
    end
  end
end
