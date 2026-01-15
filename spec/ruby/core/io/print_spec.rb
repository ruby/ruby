require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "IO#print" do
  before :each do
    @old_record_separator = $\
    @old_field_separator = $,
    suppress_warning {
      $\ = '->'
      $, = '^^'
    }
    @name = tmp("io_print")
  end

  after :each do
    suppress_warning {
      $\ = @old_record_separator
      $, = @old_field_separator
    }
    rm_r @name
  end

  it "returns nil" do
    touch(@name) { |f| f.print.should be_nil }
  end

  it "writes $_.to_s followed by $\\ (if any) to the stream if no arguments given" do
    o = mock('o')
    o.should_receive(:to_s).and_return("mockmockmock")
    $_ = o

    touch(@name) { |f| f.print }
    IO.read(@name).should == "mockmockmock#{$\}"

    # Set $_ to something known
    string = File.open(__FILE__) {|f| f.gets }

    touch(@name) { |f| f.print }
    IO.read(@name).should == "#{string}#{$\}"
  end

  it "calls obj.to_s and not obj.to_str then writes the record separator" do
    o = mock('o')
    o.should_not_receive(:to_str)
    o.should_receive(:to_s).and_return("hello")

    touch(@name) { |f| f.print(o) }

    IO.read(@name).should == "hello#{$\}"
  end

  it "writes each obj.to_s to the stream separated by $, (if any) and appends $\\ (if any) given multiple objects" do
    o, o2 = Object.new, Object.new
    def o.to_s(); 'o'; end
    def o2.to_s(); 'o2'; end

    suppress_warning {
      touch(@name) { |f| f.print(o, o2) }
    }
    IO.read(@name).should == "#{o.to_s}#{$,}#{o2.to_s}#{$\}"
  end

  it "raises IOError on closed stream" do
    -> { IOSpecs.closed_io.print("stuff") }.should raise_error(IOError)
  end
end
