describe :queue_freeze, shared: true do
  it "raises an exception when freezing" do
    queue = @object.call
    -> {
      queue.freeze
    }.should raise_error(TypeError, "cannot freeze #{queue}")
  end
end
