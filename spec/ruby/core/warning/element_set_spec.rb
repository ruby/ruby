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

  ruby_version_is '3.3' do
    it "enables or disables performance warnings" do
      original = Warning[:performance]
      begin
        Warning[:performance] = !original
        Warning[:performance].should == !original
      ensure
        Warning[:performance] = original
      end
    end
  end

  it "raises for unknown category" do
    -> { Warning[:noop] = false }.should raise_error(ArgumentError, /unknown category: noop/)
  end

  it "raises for non-Symbol category" do
    -> { Warning[42] = false }.should raise_error(TypeError)
    -> { Warning[false] = false }.should raise_error(TypeError)
    -> { Warning["noop"] = false }.should raise_error(TypeError)
  end
end
