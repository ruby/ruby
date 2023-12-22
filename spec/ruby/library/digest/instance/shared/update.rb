describe :digest_instance_update, shared: true do
  it "raises a RuntimeError if called" do
    c = Class.new do
      include Digest::Instance
    end
    -> { c.new.send(@method, "test") }.should raise_error(RuntimeError)
  end
end
