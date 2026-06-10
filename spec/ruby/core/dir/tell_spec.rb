require_relative '../../spec_helper'
require_relative 'fixtures/common'
require_relative 'shared/pos'

describe "Dir#tell" do
  it "is an alias of Dir#pos" do
    Dir.instance_method(:tell).should == Dir.instance_method(:pos)
  end
end
