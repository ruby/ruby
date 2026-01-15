describe :queue_freeze, shared: true do
  ruby_version_is ""..."3.3" do
    it "can be frozen" do
      queue = @object.call
      queue.freeze
      queue.should.frozen?
    end
  end

  ruby_version_is "3.3" do
    it "raises an exception when freezing" do
      queue = @object.call
      -> {
        queue.freeze
      }.should raise_error(TypeError, "cannot freeze #{queue}")
    end
  end
end
