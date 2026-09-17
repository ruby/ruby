require_relative 'spec_helper'

load_extension("process")

describe "CApiProcessSpecs" do
  ruby_version_is "4.1" do
    describe "rb_process_status_for" do
      it "returns a frozen Process::Status for the given process result" do
        raw_status = 42 << 8
        status = CApiProcessSpecs.new.rb_process_status_for(123, raw_status, 0)

        status.should.is_a?(Process::Status)
        status.pid.should == 123
        status.to_i.should == raw_status
        status.should.frozen?
      end
    end
  end
end
