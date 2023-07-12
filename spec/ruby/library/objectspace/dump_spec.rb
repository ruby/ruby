require_relative '../../spec_helper'
require 'objspace'

describe "ObjectSpace.dump" do
  it "dumps the content of object as JSON" do
    require 'json'
    string = ObjectSpace.dump("abc")
    dump = JSON.parse(string)

    dump['type'].should == "STRING"
    dump['value'].should == "abc"
  end

  it "dumps to string when passed output: :string" do
    string = ObjectSpace.dump("abc", output: :string)
    string.should be_kind_of(String)
    string.should include('"value":"abc"')
  end

  it "dumps to string when :output not specified" do
    string = ObjectSpace.dump("abc")
    string.should be_kind_of(String)
    string.should include('"value":"abc"')
  end

  it "dumps to a temporary file when passed output: :file" do
    file = ObjectSpace.dump("abc", output: :file)
    file.should be_kind_of(File)

    file.rewind
    content = file.read
    content.should include('"value":"abc"')
  ensure
    file.close
    File.unlink file.path
  end

  it "dumps to a temporary file when passed output: :nil" do
    file = ObjectSpace.dump("abc", output: nil)
    file.should be_kind_of(File)

    file.rewind
    file.read.should include('"value":"abc"')
  ensure
    file.close
    File.unlink file.path
  end

  it "dumps to stdout when passed output: :stdout" do
    stdout = ruby_exe('ObjectSpace.dump("abc", output: :stdout)', options: "-robjspace").chomp
    stdout.should include('"value":"abc"')
  end

  it "dumps to provided IO when passed output: IO" do
    filename = tmp("io_read.txt")
    io = File.open(filename, "w+")
    result = ObjectSpace.dump("abc", output: io)
    result.should.equal? io

    io.rewind
    io.read.should include('"value":"abc"')
  ensure
    io.close
    rm_r filename
  end

  it "raises ArgumentError when passed not supported :output value" do
    -> { ObjectSpace.dump("abc", output: Object.new) }.should raise_error(ArgumentError, /wrong output option/)
  end
end
