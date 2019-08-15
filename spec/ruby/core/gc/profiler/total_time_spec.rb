require_relative '../../../spec_helper'

describe "GC::Profiler.total_time" do
  it "returns an float" do
    GC::Profiler.total_time.should be_kind_of(Float)
  end
end
