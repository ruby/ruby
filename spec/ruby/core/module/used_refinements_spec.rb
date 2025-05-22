require_relative '../../spec_helper'

describe "Module.used_refinements" do
  it "returns list of all refinements imported in the current scope" do
    refinement_int = nil
    refinement_str = nil
    ScratchPad.record []

    m1 = Module.new do
      refine Integer do
        refinement_int = self
      end
    end

    m2 = Module.new do
      refine String do
        refinement_str = self
      end
    end

    Module.new do
      using m1
      using m2

      Module.used_refinements.each { |r| ScratchPad << r }
    end

    ScratchPad.recorded.sort_by(&:object_id).should == [refinement_int, refinement_str].sort_by(&:object_id)
  end

  it "returns empty array if does not have any refinements imported" do
    used_refinements = nil

    Module.new do
      used_refinements = Module.used_refinements
    end

    used_refinements.should == []
  end

  it "ignores refinements imported in a module that is included into the current one" do
    used_refinements = nil

    m1 = Module.new do
      refine Integer do
        nil
      end
    end

    m2 = Module.new do
      using m1
    end

    Module.new do
      include m2

      used_refinements = Module.used_refinements
    end

    used_refinements.should == []
  end

  it "returns refinements even not defined directly in a module refinements are imported from" do
    used_refinements = nil
    ScratchPad.record []

    m1 = Module.new do
      refine Integer do
        ScratchPad << self
      end
    end

    m2 = Module.new do
      include m1
    end

    Module.new do
      using m2

      used_refinements = Module.used_refinements
    end

    used_refinements.should == ScratchPad.recorded
  end
end
