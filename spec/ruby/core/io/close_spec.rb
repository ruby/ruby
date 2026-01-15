require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "IO#close" do
  before :each do
    @name = tmp('io_close.txt')
    @io = new_io @name
  end

  after :each do
    @io.close unless @io.closed?
    rm_r @name
  end

  it "closes the stream" do
    @io.close
    @io.should.closed?
  end

  it "returns nil" do
    @io.close.should == nil
  end

  it "raises an IOError reading from a closed IO" do
    @io.close
    -> { @io.read }.should raise_error(IOError)
  end

  it "raises an IOError writing to a closed IO" do
    @io.close
    -> { @io.write "data" }.should raise_error(IOError)
  end

  it 'does not close the stream if autoclose is false' do
    other_io = IO.new(@io.fileno)
    other_io.autoclose = false
    other_io.close
    -> { @io.write "data" }.should_not raise_error(IOError)
  end

  it "does nothing if already closed" do
    @io.close

    @io.close.should be_nil
  end

  it "does not call the #flush method but flushes the stream internally" do
    @io.should_not_receive(:flush)
    @io.close
    @io.should.closed?
  end

  it 'raises an IOError with a clear message' do
    matching_exception = nil

    -> do
      IOSpecs::THREAD_CLOSE_RETRIES.times do
        read_io, write_io = IO.pipe
        going_to_read = false

        thread = Thread.new do
          begin
            going_to_read = true
            read_io.read
          rescue IOError => ioe
            if ioe.message == IOSpecs::THREAD_CLOSE_ERROR_MESSAGE
              matching_exception = ioe
            end
            # try again
          end
        end

        # best attempt to ensure the thread is actually blocked on read
        Thread.pass until going_to_read && thread.stop?
        sleep(0.001)

        read_io.close
        thread.join
        write_io.close

        matching_exception&.tap {|ex| raise ex}
      end
    end.should raise_error(IOError, IOSpecs::THREAD_CLOSE_ERROR_MESSAGE)
  end
end

describe "IO#close on an IO.popen stream" do

  it "clears #pid" do
    io = IO.popen ruby_cmd('r = loop{puts "y"; 0} rescue 1; exit r'), 'r'

    io.pid.should_not == 0

    io.close

    -> { io.pid }.should raise_error(IOError)
  end

  it "sets $?" do
    io = IO.popen ruby_cmd('exit 0'), 'r'
    io.close

    $?.exitstatus.should == 0

    io = IO.popen ruby_cmd('exit 1'), 'r'
    io.close

    $?.exitstatus.should == 1
  end

  it "waits for the child to exit" do
    io = IO.popen ruby_cmd('r = loop{puts "y"; 0} rescue 1; exit r'), 'r'
    io.close

    $?.exitstatus.should_not == 0
  end

end
