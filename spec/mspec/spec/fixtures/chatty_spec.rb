unless defined?(RSpec)
  describe "Chatty#spec" do
    it "prints too much" do
      STDOUT.puts "Hello\nIt's me!"
      1.should == 1
    end
  end
end
