require_relative '../../spec_helper'

ruby_version_is "3.1" do
  platform_is :linux, :darwin, :windows, :freebsd do
    describe "Thread#native_thread_id" do
      it "returns an integer when the thread is alive" do
        Thread.current.native_thread_id.should be_kind_of(Integer)
      end

      it "returns nil when the thread is not running" do
        t = Thread.new {}
        t.join
        t.native_thread_id.should == nil
      end

      it "each thread has different native thread id" do
        t = Thread.new { sleep }
        Thread.pass until t.stop?
        main_thread_id = Thread.current.native_thread_id
        t_thread_id = t.native_thread_id

        if ruby_version_is "3.3"
          # native_thread_id can be nil on a M:N scheduler
          t_thread_id.should be_kind_of(Integer) if t_thread_id != nil
        else
          t_thread_id.should be_kind_of(Integer)
        end

        main_thread_id.should_not == t_thread_id

        t.run
        t.join
        t.native_thread_id.should == nil
      end
    end
  end
end
