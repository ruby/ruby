require_relative '../../spec_helper'

ruby_version_is "2.5" do
  describe "Binding#irb" do
    it "creates an IRB session with the binding in scope" do
      irb_fixture = fixture __FILE__, "irb.rb"
      irbrc_fixture = fixture __FILE__, "irbrc"

      out = IO.popen([{"IRBRC"=>irbrc_fixture}, *ruby_exe, irb_fixture], "r+") do |pipe|
        pipe.puts "a ** 2"
        pipe.puts "exit"
        pipe.readlines.map(&:chomp)
      end

      out[-3..-1].should == ["a ** 2", "100", "exit"]
    end
  end
end
