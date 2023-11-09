require_relative '../../spec_helper'

describe "GC.auto_compact" do
  it "can set and get a boolean value" do
    begin
      GC.auto_compact = GC.auto_compact
    rescue NotImplementedError # platform does not support autocompact
      skip
    end

    original = GC.auto_compact
    begin
      GC.auto_compact = !original
    rescue NotImplementedError # platform does not support autocompact
      skip
    end

    begin
      GC.auto_compact.should == !original
    ensure
      GC.auto_compact = original
    end
  end
end
