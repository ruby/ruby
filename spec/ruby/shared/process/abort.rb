describe :process_abort, shared: true do
  before :each do
    @stderr, $stderr = $stderr, IOStub.new
  end

  after :each do
    $stderr = @stderr
  end

  it "raises a SystemExit exception" do
    -> { @object.abort }.should.raise(SystemExit)
  end

  it "sets the exception message to the given message" do
    -> { @object.abort "message" }.should.raise { |e| e.message.should == "message" }
  end

  it "sets the exception status code of 1" do
    -> { @object.abort }.should.raise { |e| e.status.should == 1 }
  end

  it "prints the specified message to STDERR" do
    -> { @object.abort "a message" }.should.raise(SystemExit)
    $stderr.should =~ /a message/
  end

  it "coerces the argument with #to_str" do
    str = mock('to_str')
    str.should_receive(:to_str).any_number_of_times.and_return("message")
    -> { @object.abort str }.should.raise(SystemExit, "message")
  end

  it "raises TypeError when given a non-String object" do
    -> { @object.abort 123 }.should.raise(TypeError)
  end
end
