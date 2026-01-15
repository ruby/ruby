require_relative '../../spec_helper'
require 'tmpdir'

describe "Binding#irb" do
  it "creates an IRB session with the binding in scope" do
    irb_fixture = fixture __FILE__, "irb.rb"
    envs = %w[IRBRC HOME XDG_CONFIG_HOME].to_h {|e| [e, nil]}

    out = Dir.mktmpdir do |dir|
      IO.popen([envs, *ruby_exe, irb_fixture, chdir: dir], "r+") do |pipe|
        pipe.puts "a ** 2"
        pipe.puts "exit"
        pipe.readlines.map(&:chomp).reject(&:empty?)
      end
    end

    out.last(3).should == ["a ** 2", "100", "exit"]
  end
end
