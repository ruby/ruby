require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "StringIO#sync" do
  it "returns true" do
    StringIO.new('').sync.should be_true
  end
end

describe "StringIO#sync=" do
  before :each do
    @io = StringIO.new('')
  end

  it "does not change 'sync' status" do
    @io.sync = false
    @io.sync.should be_true
  end
end
