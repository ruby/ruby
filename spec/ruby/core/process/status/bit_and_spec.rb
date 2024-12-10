require_relative '../../../spec_helper'

describe "Process::Status#&" do
  it "returns a bitwise and of the integer status of an exited child" do
    suppress_warning do
      ruby_exe("exit(29)", exit_status: 29)
      ($? & 0).should == 0
      ($? & $?.to_i).should == $?.to_i

      # Actual value is implementation specific
      platform_is :linux do
        # 29 == 0b11101
        ($? & 0b1011100000000).should == 0b1010100000000
      end
    end
  end

  ruby_version_is "3.3" do
    it "raises an ArgumentError if mask is negative" do
      suppress_warning do
        ruby_exe("exit(0)")
        -> {
          $? & -1
        }.should raise_error(ArgumentError, 'negative mask value: -1')
      end
    end

    it "shows a deprecation warning" do
      ruby_exe("exit(0)")
      -> {
        $? & 0
      }.should complain(/warning: Process::Status#& is deprecated and will be removed .*use other Process::Status predicates instead/)
    end
  end
end
