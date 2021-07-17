require_relative '../../spec_helper'

ruby_version_is '2.7' do
  describe "Warning.[]=" do
    it "emits and suppresses warnings for :deprecated" do
      ruby_exe('Warning[:deprecated] = true; $; = ""', args: "2>&1").should =~ /is deprecated/
      ruby_exe('Warning[:deprecated] = false; $; = ""', args: "2>&1").should == ""
    end

    describe ":experimental" do
      before do
        ruby_version_is ""..."3.0" do
          @src = 'case [0, 1]; in [a, b]; end'
        end

        ruby_version_is "3.0" do
          @src = 'warn "This is experimental warning.", category: :experimental'
        end
      end

      it "emits and suppresses warnings for :experimental" do
        ruby_exe("Warning[:experimental] = true; eval('#{@src}')", args: "2>&1").should =~ /is experimental/
        ruby_exe("Warning[:experimental] = false; eval('#{@src}')", args: "2>&1").should == ""
      end
    end

    it "raises for unknown category" do
      -> { Warning[:noop] = false }.should raise_error(ArgumentError, /unknown category: noop/)
    end
  end
end
