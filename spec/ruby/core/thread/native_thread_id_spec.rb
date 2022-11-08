require_relative '../../spec_helper'

if ruby_version_is "3.1" and Thread.method_defined?(:native_thread_id)
  # This method is very platform specific

  describe "Thread#native_thread_id" do
    it "returns an integer when the thread is alive" do
      Thread.current.native_thread_id.should be_kind_of(Integer)
    end

    it "returns nil when the thread is not running" do
      t = Thread.new {}
      t.join
      t.native_thread_id.should == nil
    end
  end
end
