require_relative '../../../spec_helper'

describe "GC::Profiler.disable" do
  before do
    @status = GC::Profiler.enabled?
  end

  after do
    @status ? GC::Profiler.enable : GC::Profiler.disable
  end

  it "disables the profiler" do
    GC::Profiler.disable
    GC::Profiler.should_not.enabled?
  end
end
