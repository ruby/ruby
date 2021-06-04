require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe :hash_index, shared: true do
  it "returns the corresponding key for value" do
    suppress_warning do # for Hash#index
      { 2 => 'a', 1 => 'b' }.send(@method, 'b').should == 1
    end
  end

  it "returns nil if the value is not found" do
    suppress_warning do # for Hash#index
      { a: -1, b: 3.14, c: 2.718 }.send(@method, 1).should be_nil
    end
  end

  it "doesn't return default value if the value is not found" do
    suppress_warning do # for Hash#index
      Hash.new(5).send(@method, 5).should be_nil
    end
  end

  it "compares values using ==" do
    suppress_warning do # for Hash#index
      { 1 => 0 }.send(@method, 0.0).should == 1
      { 1 => 0.0 }.send(@method, 0).should == 1
    end

    needle = mock('needle')
    inhash = mock('inhash')
    inhash.should_receive(:==).with(needle).and_return(true)

    suppress_warning do # for Hash#index
      { 1 => inhash }.send(@method, needle).should == 1
    end
  end
end
