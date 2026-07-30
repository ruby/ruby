require_relative '../../spec_helper'

describe "Process._fork" do
  it "for #respond_to? returns the same as Process.respond_to?(:fork)" do
    Process.respond_to?(:_fork).should == Process.respond_to?(:fork)
  end

  # Using respond_to? in a guard here is OK because the correct semantics
  # are that _fork is implemented if and only if fork is (see above).
  guard_not -> { Process.respond_to?(:fork) } do
    it "raises a NotImplementedError when called" do
      -> { Process._fork }.should.raise(NotImplementedError)
    end
  end

  guard -> { Process.respond_to?(:fork) } do
    it "is called by Process#fork" do
      Process.should_receive(:_fork).once.and_return(42)

      pid = Process.fork {}
      pid.should.equal?(42)
    end

    ruby_version_is "4.1" do
      it "allows Process#fork to return an Integer-like object from Process._fork" do
        mock_pid = Data.define(:to_int) { alias to_i to_int }.new(42)
        Process.should_receive(:_fork).once.and_return(mock_pid)

        pid = Process.fork {}
        pid.should.equal?(mock_pid)
      end
    end
  end
end
