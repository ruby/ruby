require_relative '../../../spec_helper'

describe "Process::Status#>>" do
  it "returns a right shift of the integer status of an exited child" do
    suppress_warning do
      ruby_exe("exit(29)", exit_status: 29)
      ($? >> 0).should == $?.to_i
      ($? >> 1).should == $?.to_i >> 1

      # Actual value is implementation specific
      platform_is :linux do
        ($? >> 8).should == 29
      end
    end
  end

  ruby_version_is "3.3" do
    it "raises an ArgumentError if shift value is negative" do
      suppress_warning do
        ruby_exe("exit(0)")
        -> {
          $? >> -1
        }.should raise_error(ArgumentError, 'negative shift value: -1')
      end
    end

    it "shows a deprecation warning" do
      ruby_exe("exit(0)")
      -> {
        $? >> 0
      }.should complain(/warning: Process::Status#>> is deprecated and will be removed .*use other Process::Status attributes instead/)
    end
  end
end
