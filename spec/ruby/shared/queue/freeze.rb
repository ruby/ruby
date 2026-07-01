describe :queue_freeze, shared: true do
  it "raises an exception when freezing" do
    queue = @object.call
    -> {
      queue.freeze
    }.should.raise(TypeError, "cannot freeze #{queue}")
  end
end
