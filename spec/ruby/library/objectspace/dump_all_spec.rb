require_relative '../../spec_helper'
require 'objspace'

describe "ObjectSpace.dump_all" do
  it "dumps Ruby heap to string when passed output: :string" do
    stdout = ruby_exe(<<~RUBY, options: "-robjspace")
      string = "abc"
      dump = ObjectSpace.dump_all(output: :string)
      puts dump.class
      puts dump.include?('"value":"abc"')
    RUBY

    stdout.should == "String\ntrue\n"
  end

  it "dumps Ruby heap to a temporary file when passed output: :file" do
    stdout = ruby_exe(<<~RUBY, options: "-robjspace")
      string = "abc"
      file = ObjectSpace.dump_all(output: :file)

      begin
        file.flush
        file.rewind
        content = file.read

        puts file.class
        puts content.include?('"value":"abc"')
      ensure
        file.close
        File.unlink file.path
      end
    RUBY

    stdout.should == "File\ntrue\n"
  end

  it "dumps Ruby heap to a temporary file when :output not specified" do
    stdout = ruby_exe(<<~RUBY, options: "-robjspace")
      string = "abc"
      file = ObjectSpace.dump_all

      begin
        file.flush
        file.rewind
        content = file.read

        puts file.class
        puts content.include?('"value":"abc"')
      ensure
        file.close
        File.unlink file.path
      end
    RUBY

    stdout.should == "File\ntrue\n"
  end

  it "dumps Ruby heap to a temporary file when passed output: :nil" do
    stdout = ruby_exe(<<~RUBY, options: "-robjspace")
    string = "abc"
    file = ObjectSpace.dump_all(output: nil)

    begin
      file.flush
      file.rewind
      content = file.read

      puts file.class
      puts content.include?('"value":"abc"')
    ensure
      file.close
      File.unlink file.path
    end
    RUBY

    stdout.should == "File\ntrue\n"
  end

  it "dumps Ruby heap to stdout when passed output: :stdout" do
    stdout = ruby_exe(<<~RUBY, options: "-robjspace")
      string = "abc"
      ObjectSpace.dump_all(output: :stdout)
    RUBY

    stdout.should include('"value":"abc"')
  end

  it "dumps Ruby heap to provided IO when passed output: IO" do
    stdout = ruby_exe(<<~RUBY, options: "-robjspace -rtempfile")
      string = "abc"
      io = Tempfile.create("object_space_dump_all")

      begin
        result = ObjectSpace.dump_all(output: io)
        io.rewind
        content = io.read

        puts result.equal?(io)
        puts content.include?('"value":"abc"')
      ensure
        io.close
        File.unlink io.path
      end
    RUBY

    stdout.should == "true\ntrue\n"
  end

  it "raises ArgumentError when passed not supported :output value" do
    -> { ObjectSpace.dump_all(output: Object.new) }.should raise_error(ArgumentError, /wrong output option/)
  end
end
