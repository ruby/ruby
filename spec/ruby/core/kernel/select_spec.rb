require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#select" do
  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:select)
  end

  it 'does not block when timeout is 0' do
    IO.pipe do |read, write|
      select([read], [], [], 0).should == nil
      write.write 'data'
      select([read], [], [], 0).should == [[read], [], []]
    end
  end
end

describe "Kernel.select" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:select)
  end
end
