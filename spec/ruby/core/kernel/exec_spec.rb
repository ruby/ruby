require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#exec" do
  it "is a private method" do
    Kernel.should have_private_instance_method(:exec)
  end

  it "runs the specified command, replacing current process" do
    ruby_exe('exec "echo hello"; puts "fail"').should == "hello\n"
  end
end

describe "Kernel.exec" do
  it "runs the specified command, replacing current process" do
    ruby_exe('Kernel.exec "echo hello"; puts "fail"').should == "hello\n"
  end
end
