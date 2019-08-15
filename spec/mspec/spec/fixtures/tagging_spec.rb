# encoding: utf-8
unless defined?(RSpec)
  describe "Tag#me" do
    it "passes" do
      1.should == 1
    end

    it "errors" do
      1.should == 2
    end

    it "érròrs in unicode" do
      1.should == 2
    end
  end
end
