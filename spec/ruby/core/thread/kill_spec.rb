require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/exit'

describe "Thread#kill" do
  it_behaves_like :thread_exit, :kill
end

describe "Thread#kill!" do
  it "needs to be reviewed for spec completeness"
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
