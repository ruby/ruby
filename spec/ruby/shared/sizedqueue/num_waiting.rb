describe :sizedqueue_num_waiting, shared: true do
  it "reports the number of threads waiting to push" do
    q = @object.call(1)
    q.push(1)
    t = Thread.new { q.push(2) }
    sleep 0.05 until t.stop?
    q.num_waiting.should == 1

    q.pop
    t.join
  end
end
