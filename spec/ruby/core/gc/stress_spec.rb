require_relative '../../spec_helper'

describe "GC.stress" do
  after :each do
    # make sure that we never leave these tests in stress enabled GC!
    GC.stress = false
  end

  it "returns current status of GC stress mode" do
    GC.stress.should be_false
    GC.stress = true
    GC.stress.should be_true
    GC.stress = false
    GC.stress.should be_false
  end
end

describe "GC.stress=" do
  after :each do
    GC.stress = false
  end

  it "accepts true, false, and integers" do
    GC.stress = true
    GC.stress.should be_true
    GC.stress = false
    GC.stress.should be_false
    GC.stress = 4
    GC.stress.should equal 4
  end

  it "tries to convert non-boolean argument to an integer using to_int" do
    a = mock('4')
    a.should_receive(:to_int).and_return(4)

    GC.stress = a
    GC.stress.should equal 4
  end

  it "raises TypeError for non-boolean and `to_int` types" do
    -> { GC.stress = nil }.should raise_error(TypeError)
    -> { GC.stress = Object.new }.should raise_error(TypeError)
    -> { GC.stress = :hello }.should raise_error(TypeError)
  end
end
