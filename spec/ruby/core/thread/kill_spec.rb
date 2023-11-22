require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/exit'

# This spec randomly kills mspec worker like: https://ci.appveyor.com/project/ruby/ruby/builds/19473223/job/f69derxnlo09xhuj
# TODO: Investigate the cause or at least print helpful logs, and remove this `platform_is_not` guard.
platform_is_not :mingw do
  describe "Thread#kill" do
    it_behaves_like :thread_exit, :kill
  end

  describe "Thread.kill" do
    it "causes the given thread to exit" do
      thread = Thread.new { sleep }
      Thread.pass while thread.status and thread.status != "sleep"
      Thread.kill(thread).should == thread
      thread.join
      thread.status.should be_false
    end
  end
end
