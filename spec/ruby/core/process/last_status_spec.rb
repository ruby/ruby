require_relative '../../spec_helper'

ruby_version_is '2.5' do
  describe 'Process#last_status' do
    it 'returns the status of the last executed child process in the current thread' do
      pid = Process.wait Process.spawn("exit 0")
      Process.last_status.pid.should == pid
    end

    it 'returns nil if no child process has been ever executed in the current thread' do
      Thread.new do
        Process.last_status.should == nil
      end.join
    end

    it 'raises an ArgumentError if any arguments are provided' do
      -> { Process.last_status(1) }.should raise_error(ArgumentError)
    end
  end
end
