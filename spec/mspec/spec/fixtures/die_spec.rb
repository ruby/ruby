unless defined?(RSpec)
  describe "Deadly#spec" do
    it "dies" do
      abort "DEAD"
    end
  end
end
