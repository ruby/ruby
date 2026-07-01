require_relative '../../../spec_helper'

describe "GC::Profiler.total_time" do
  it "returns an float" do
    GC::Profiler.total_time.should.is_a?(Float)
  end
end
