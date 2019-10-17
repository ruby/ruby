require_relative '../../spec_helper'
require 'weakref'

describe "WeakRef#new" do
  it "creates a subclass correctly" do
    wr2 = Class.new(WeakRef) {
      def __getobj__
        :dummy
      end
    }
    wr2.new(Object.new).__getobj__.should == :dummy
  end
end
