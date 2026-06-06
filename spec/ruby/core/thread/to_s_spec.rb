require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Thread#to_s" do
  it "returns a description including file and line number" do
    thread, line = Thread.new { "hello" }, __LINE__
    thread.join
    thread.to_s.should =~ /^#<Thread:([^ ]*?) #{Regexp.escape __FILE__}:#{line} \w+>$/
  end

  it "has a binary encoding" do
    ThreadSpecs.status_of_current_thread.to_s.encoding.should == Encoding::BINARY
  end

  it "can check it's own status" do
    ThreadSpecs.status_of_current_thread.to_s.should.include?('run')
  end

  it "describes a running thread" do
    ThreadSpecs.status_of_running_thread.to_s.should.include?('run')
  end

  it "describes a sleeping thread" do
    ThreadSpecs.status_of_sleeping_thread.to_s.should.include?('sleep')
  end

  it "describes a blocked thread" do
    ThreadSpecs.status_of_blocked_thread.to_s.should.include?('sleep')
  end

  it "describes a completed thread" do
    ThreadSpecs.status_of_completed_thread.to_s.should.include?('dead')
  end

  it "describes a killed thread" do
    ThreadSpecs.status_of_killed_thread.to_s.should.include?('dead')
  end

  it "describes a thread with an uncaught exception" do
    ThreadSpecs.status_of_thread_with_uncaught_exception.to_s.should.include?('dead')
  end

  it "describes a dying sleeping thread" do
    ThreadSpecs.status_of_dying_sleeping_thread.to_s.should.include?('sleep')
  end

  it "reports aborting on a killed thread" do
    ThreadSpecs.status_of_dying_running_thread.to_s.should.include?('aborting')
  end

  it "reports aborting on a killed thread after sleep" do
    ThreadSpecs.status_of_dying_thread_after_sleep.to_s.should.include?('aborting')
  end
end
