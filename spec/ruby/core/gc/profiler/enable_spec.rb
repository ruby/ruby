require_relative '../../../spec_helper'

describe "GC::Profiler.enable" do

  before do
    @status = GC::Profiler.enabled?
  end

  after do
    @status ? GC::Profiler.enable : GC::Profiler.disable
  end

  it "enables the profiler" do
    GC::Profiler.enable
    GC::Profiler.should.enabled?
  end
end
