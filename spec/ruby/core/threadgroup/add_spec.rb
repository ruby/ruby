require_relative '../../spec_helper'

describe "ThreadGroup#add" do
  before :each do
    @q1, @q2 = Queue.new, Queue.new
    @thread = Thread.new { @q1 << :go; @q2.pop }
    @q1.pop
  end

  after :each do
    @q2 << :done
    @thread.join
  end

  # This spec randomly kills mspec worker like: https://ci.appveyor.com/project/ruby/ruby/build/9806/job/37tx2atojy96227m
  # TODO: Investigate the cause or at least print helpful logs, and remove this `platform_is_not` guard.
  platform_is_not :mingw do
    it "adds the given thread to a group and returns self" do
      @thread.group.should_not == nil

      tg = ThreadGroup.new
      tg.add(@thread).should == tg
      @thread.group.should == tg
      tg.list.include?(@thread).should == true
    end

    it "removes itself from any other threadgroup" do
      tg1 = ThreadGroup.new
      tg2 = ThreadGroup.new

      tg1.add(@thread)
      @thread.group.should == tg1
      tg2.add(@thread)
      @thread.group.should == tg2
      tg2.list.include?(@thread).should == true
      tg1.list.include?(@thread).should == false
    end
  end
end
