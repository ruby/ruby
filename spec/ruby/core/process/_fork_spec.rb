require_relative '../../spec_helper'

ruby_version_is "3.1" do
  describe "Process._fork" do
    it "for #respond_to? returns the same as Process.respond_to?(:fork)" do
      Process.respond_to?(:_fork).should == Process.respond_to?(:fork)
    end

    guard_not -> { Process.respond_to?(:fork) } do
      it "raises a NotImplementedError when called" do
        -> { Process._fork }.should raise_error(NotImplementedError)
      end
    end

    guard -> { Process.respond_to?(:fork) } do
      it "is called by Process#fork" do
        Process.should_receive(:_fork).once.and_return(42)

        pid = Process.fork {}
        pid.should equal(42)
      end
    end
  end
end
