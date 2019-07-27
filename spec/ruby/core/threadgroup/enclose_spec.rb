require_relative '../../spec_helper'

describe "ThreadGroup#enclose" do
  before :each do
    @q1, @q2 = Queue.new, Queue.new
    @thread = Thread.new { @q1 << :go; @q2.pop }
    @q1.pop
  end

  after :each do
    @q2 << :done
    @thread.join
  end

  it "raises a ThreadError if attempting to move a Thread from an enclosed ThreadGroup" do
    thread_group = ThreadGroup.new
    default_group = @thread.group
    thread_group.add(@thread)
    thread_group.enclose
    -> do
      default_group.add(@thread)
    end.should raise_error(ThreadError)
  end
end
