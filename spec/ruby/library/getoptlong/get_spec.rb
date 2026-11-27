require_relative '../../spec_helper'
require 'getoptlong'

describe "GetoptLong#get" do
  before :each do
    @opts = GetoptLong.new(
      [ '--size', '-s',             GetoptLong::REQUIRED_ARGUMENT ],
      [ '--verbose', '-v',          GetoptLong::NO_ARGUMENT ],
      [ '--query', '-q',            GetoptLong::NO_ARGUMENT ],
      [ '--check', '--valid', '-c', GetoptLong::NO_ARGUMENT ]
    )
    @opts.quiet = true # silence using $deferr
  end

  it "returns the next option name and its argument as an Array" do
    argv [ "--size", "10k", "-v", "-q", "a.txt", "b.txt" ] do
      @opts.get.should == [ "--size", "10k" ]
      @opts.get.should == [ "--verbose", "" ]
      @opts.get.should == [ "--query", ""]
      @opts.get.should == nil
    end
  end

  it "shifts ARGV on each call" do
    argv [ "--size", "10k", "-v", "-q", "a.txt", "b.txt" ] do
      @opts.get
      ARGV.should == [ "-v", "-q", "a.txt", "b.txt" ]

      @opts.get
      ARGV.should == [ "-q", "a.txt", "b.txt" ]

      @opts.get
      ARGV.should == [ "a.txt", "b.txt" ]

      @opts.get
      ARGV.should == [ "a.txt", "b.txt" ]
    end
  end

  it "terminates processing when encountering '--'" do
    argv [ "--size", "10k", "--", "-v", "-q", "a.txt", "b.txt" ] do
      @opts.get
      ARGV.should == ["--", "-v", "-q", "a.txt", "b.txt"]

      @opts.get
      ARGV.should ==  ["-v", "-q", "a.txt", "b.txt"]

      @opts.get
      ARGV.should ==  ["-v", "-q", "a.txt", "b.txt"]
    end
  end

  it "raises a if an argument was required, but none given" do
    argv [ "--size" ] do
      -> { @opts.get }.should.raise(GetoptLong::MissingArgument)
    end
  end

  # https://bugs.ruby-lang.org/issues/13858
  it "returns multiline argument" do
    argv [ "--size=\n10k\n" ] do
      @opts.get.should == [ "--size", "\n10k\n" ]
    end
  end
end
