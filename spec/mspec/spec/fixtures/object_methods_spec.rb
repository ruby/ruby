unless defined?(RSpec)
  describe "Object" do
    it ".public_instance_methods(false) is empty" do
      Object.public_instance_methods(false).sort.should ==
        [:should, :should_not, :should_not_receive, :should_receive, :stub!]
    end
  end
end
