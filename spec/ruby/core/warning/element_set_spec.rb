require_relative '../../spec_helper'

describe "Warning.[]=" do
  it "emits and suppresses warnings for :deprecated" do
    ruby_exe('Warning[:deprecated] = true; $; = ""', args: "2>&1").should =~ /is deprecated/
    ruby_exe('Warning[:deprecated] = false; $; = ""', args: "2>&1").should == ""
  end

  describe ":experimental" do
    before do
      @src = 'warn "This is experimental warning.", category: :experimental'
    end

    it "emits and suppresses warnings for :experimental" do
      ruby_exe("Warning[:experimental] = true; eval('#{@src}')", args: "2>&1").should =~ /is experimental/
      ruby_exe("Warning[:experimental] = false; eval('#{@src}')", args: "2>&1").should == ""
    end
  end

  it "enables or disables performance warnings" do
    original = Warning[:performance]
    begin
      Warning[:performance] = !original
      Warning[:performance].should == !original
    ensure
      Warning[:performance] = original
    end
  end

  it "raises for unknown category" do
    -> { Warning[:noop] = false }.should.raise(ArgumentError, /unknown category: noop/)
  end

  it "raises for non-Symbol category" do
    -> { Warning[42] = false }.should.raise(TypeError)
    -> { Warning[false] = false }.should.raise(TypeError)
    -> { Warning["noop"] = false }.should.raise(TypeError)
  end
end
