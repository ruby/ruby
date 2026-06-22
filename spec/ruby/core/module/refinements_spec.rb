require_relative '../../spec_helper'

describe "Module#refinements" do
  it "returns refinements defined in a module" do
    ScratchPad.record []

    m = Module.new do
      refine String do
        ScratchPad << self
      end

      refine Array do
        ScratchPad << self
      end
    end

    m.refinements.sort_by(&:object_id).should == ScratchPad.recorded.sort_by(&:object_id)
  end

  it "does not return refinements defined in the included module" do
    ScratchPad.record []

    m1 = Module.new do
      refine Integer do
        nil
      end
    end

    m2 = Module.new do
      include m1

      refine String do
        ScratchPad << self
      end
    end

    m2.refinements.should == ScratchPad.recorded
  end

  it "returns an empty array if no refinements defined in a module" do
    Module.new.refinements.should == []
  end
end
