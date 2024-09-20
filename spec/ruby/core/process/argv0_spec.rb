require_relative '../../spec_helper'

describe "Process.argv0" do
  it "returns a String" do
    Process.argv0.should be_kind_of(String)
  end

  it "is the path given as the main script and the same as __FILE__" do
    script = "fixtures/argv0.rb"

    Dir.chdir(__dir__) do
      ruby_exe(script).should == "#{script}\n#{script}\nOK"
    end
  end

  ruby_bug "#19597", ""..."3.3" do
    it "returns a frozen object" do
      Process.argv0.should.frozen?
    end
  end

  it "returns every time the same object" do
    Process.argv0.should.equal?(Process.argv0)
  end
end
