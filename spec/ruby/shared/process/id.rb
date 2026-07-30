def it_returns_process_id(&new_pid)
  ruby_version_is ""..."4.1" do
    it "returns the process ID as an Integer" do
      pid = instance_exec(&new_pid)
      Process.waitpid(pid)
      pid.should.instance_of?(Integer)
    end
  end

  ruby_version_is "4.1" do
    it "returns the process ID as a Process::ID" do
      pid = instance_exec(&new_pid)
      Process.waitpid(pid)
      pid.should.instance_of?(Process::ID)
      pid.to_i.should.instance_of?(Integer)
    end

    it "detaches the process ID" do
      pid = instance_exec(&new_pid)
      thread = pid.detach
      thread.value.success?.should == true
    end
  end
end
