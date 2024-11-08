require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#select" do
  it "is a private method" do
    Kernel.should have_private_instance_method(:select)
  end
end

describe "Kernel.select" do
  it 'does not block when timeout is 0' do
    IO.pipe do |read, write|
      select([read], [], [], 0).should == nil
      write.write 'data'
      select([read], [], [], 0).should == [[read], [], []]
    end
  end
end
