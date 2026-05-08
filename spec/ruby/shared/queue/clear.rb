describe :queue_clear, shared: true do
  it "removes all objects from the queue" do
    queue = @object.call
    queue << Object.new
    queue << 1
    queue.empty?.should == false
    queue.clear
    queue.empty?.should == true
  end

  # TODO: test for atomicity of Queue#clear
end
