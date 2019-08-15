describe :sizedqueue_enq, shared: true do
  it "blocks if queued elements exceed size" do
    q = @object.call(1)

    q.size.should == 0
    q.send(@method, :first_element)
    q.size.should == 1

    blocked_thread = Thread.new { q.send(@method, :second_element) }
    sleep 0.01 until blocked_thread.stop?

    q.size.should == 1
    q.pop.should == :first_element

    blocked_thread.join
    q.size.should == 1
    q.pop.should == :second_element
    q.size.should == 0
  end

  it "raises a ThreadError if queued elements exceed size when not blocking" do
    q = @object.call(2)

    non_blocking = true
    add_to_queue = -> { q.send(@method, Object.new, non_blocking) }

    q.size.should == 0
    add_to_queue.call
    q.size.should == 1
    add_to_queue.call
    q.size.should == 2
    add_to_queue.should raise_error(ThreadError)
  end

  it "interrupts enqueuing threads with ClosedQueueError when the queue is closed" do
    q = @object.call(1)
    q << 1

    t = Thread.new {
      -> { q.send(@method, 2) }.should raise_error(ClosedQueueError)
    }

    Thread.pass until q.num_waiting == 1

    q.close

    t.join
    q.pop.should == 1
  end
end
