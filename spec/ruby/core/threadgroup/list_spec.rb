require_relative '../../spec_helper'

describe "ThreadGroup#list" do
  it "returns the list of threads in the group" do
    q = Queue.new
    th1 = Thread.new { q << :go; sleep }
    q.pop.should == :go
    tg = ThreadGroup.new
    tg.add(th1)
    tg.list.should include(th1)

    th2 = Thread.new { q << :go; sleep }
    q.pop.should == :go

    tg.add(th2)
    (tg.list & [th1, th2]).should include(th1, th2)

    Thread.pass while th1.status and th1.status != 'sleep'
    Thread.pass while th2.status and th2.status != 'sleep'
    th1.run; th1.join
    th2.run; th2.join
  end
end
