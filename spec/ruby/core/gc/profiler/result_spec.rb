require_relative '../../../spec_helper'

describe "GC::Profiler.result" do
  it "returns a string" do
    GC::Profiler.result.should.is_a?(String)
  end
end
