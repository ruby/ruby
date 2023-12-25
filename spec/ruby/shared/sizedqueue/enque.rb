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
      -> { q.send(@method, 2) }.should raise_error(ClosedQueueError, "queue closed")
    }

    Thread.pass until q.num_waiting == 1

    q.close

    t.join
    q.pop.should == 1
  end

  describe "with a timeout" do
    ruby_version_is "3.2" do
      it "returns self if the item was pushed in time" do
        q = @object.call(1)
        q << 1

        t = Thread.new {
          q.send(@method, 2, timeout: 1).should == q
        }
        Thread.pass until t.status == "sleep" && q.num_waiting == 1
        q.pop
        t.join
      end

      it "does nothing if the timeout is nil" do
        q = @object.call(1)
        q << 1
        t = Thread.new {
          q.send(@method, 2, timeout: nil).should == q
        }
        t.join(0.2).should == nil
        q.pop
        t.join
      end

      it "returns nil if no space is available and timeout is 0" do
        q = @object.call(1)
        q.send(@method, 1, timeout: 0).should == q
        q.send(@method, 2, timeout: 0).should == nil
      end

      it "returns nil if no space is available in time" do
        q = @object.call(1)
        q << 1
        t = Thread.new {
          q.send(@method, 2, timeout: 0.1).should == nil
        }
        t.join
      end

      it "raise TypeError if timeout is not a valid numeric" do
        q = @object.call(1)
        -> { q.send(@method, 2, timeout: "1") }.should raise_error(
          TypeError,
          "no implicit conversion to float from string",
        )

        -> { q.send(@method, 2, timeout: false) }.should raise_error(
          TypeError,
          "no implicit conversion to float from false",
        )
      end

      it "raise ArgumentError if non_block = true is passed too" do
        q = @object.call(1)
        -> { q.send(@method, 2, true, timeout: 1) }.should raise_error(
          ArgumentError,
          "can't set a timeout if non_block is enabled",
        )
      end

      it "raise ClosedQueueError when closed before enqueued" do
        q = @object.call(1)
        q.close
        -> { q.send(@method, 2, timeout: 1) }.should raise_error(ClosedQueueError, "queue closed")
      end

      it "interrupts enqueuing threads with ClosedQueueError when the queue is closed" do
        q = @object.call(1)
        q << 1

        t = Thread.new {
          -> { q.send(@method, 1, timeout: 10) }.should raise_error(ClosedQueueError, "queue closed")
        }

        Thread.pass until q.num_waiting == 1

        q.close

        t.join
        q.pop.should == 1
      end
    end
  end
end
