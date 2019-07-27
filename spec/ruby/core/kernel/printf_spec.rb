require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/sprintf'
require "stringio"

describe "Kernel#printf" do
  it "is a private method" do
    Kernel.should have_private_instance_method(:printf)
  end
end

describe "Kernel.printf" do

  before :each do
    @stdout = $stdout
    @name = tmp("kernel_puts.txt")
    $stdout = new_io @name
  end

  after :each do
    $stdout.close
    $stdout = @stdout
    rm_r @name
  end

  it "writes to stdout when a string is the first argument" do
    $stdout.should_receive(:write).with("string")
    Kernel.printf("%s", "string")
  end

  it "calls write on the first argument when it is not a string" do
    object = mock('io')
    object.should_receive(:write).with("string")
    Kernel.printf(object, "%s", "string")
  end

  describe "formatting" do
    context "io is specified" do
      it_behaves_like :kernel_sprintf, -> format, *args {
        io = StringIO.new
        printf(io, format, *args)
        io.string
      }
    end

    context "io is not specified" do
      it_behaves_like :kernel_sprintf, -> format, *args {
        stdout = $stdout

        begin
          $stdout = io = StringIO.new
          printf(format, *args)
          io.string
        ensure
          $stdout = stdout
        end
      }
    end
  end
end
