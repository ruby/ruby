unless defined?(RSpec)
  describe "Foo#bar" do
    it "passes" do
      1.should == 1
    end

    it "errors" do
      1.should == 2
    end

    it "fails" do
      raise "failure"
    end
  end
end
