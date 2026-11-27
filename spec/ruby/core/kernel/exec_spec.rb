require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#exec" do
  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:exec)
  end

  it "runs the specified command, replacing current process" do
    ruby_exe('exec "echo hello"; puts "fail"').should == "hello\n"
  end
end

describe "Kernel.exec" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:exec)
  end
end
