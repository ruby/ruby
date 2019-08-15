require_relative '../../spec_helper'
require 'monitor'

describe "MonitorMixin#mon_initialize" do
  it "can be called in initialize_copy to get a new Mutex and used with synchronize" do
    cls = Class.new do
      include MonitorMixin

      def initialize(*array)
        mon_initialize
        @array = array
      end

      def to_a
        synchronize { @array.dup }
      end

      def initialize_copy(other)
        mon_initialize

        synchronize do
          @array = other.to_a
        end
      end
    end

    instance = cls.new(1, 2, 3)
    copy = instance.dup
    copy.should_not equal(instance)
  end
end
