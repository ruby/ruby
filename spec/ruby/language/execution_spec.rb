require_relative '../spec_helper'

describe "``" do
  it "returns the output of the executed sub-process" do
    ip = 'world'
    `echo disc #{ip}`.should == "disc world\n"
  end

  it "can be redefined and receive a frozen string as argument" do
    called = false
    runner = Object.new

    runner.singleton_class.define_method(:`) do |str|
      called = true

      str.should == "test command"
      str.frozen?.should == true
    end

    runner.instance_exec do
      `test command`
    end

    called.should == true
  end

  it "the argument isn't frozen if it contains interpolation" do
    called = false
    runner = Object.new

    runner.singleton_class.define_method(:`) do |str|
      called = true

      str.should == "test command"
      str.frozen?.should == false
      str << "mutated"
    end

    2.times do
      runner.instance_exec do
        `test #{:command}`
      end
    end

    called.should == true
  end
end

describe "%x" do
  it "is the same as ``" do
    ip = 'world'
    %x(echo disc #{ip}).should == "disc world\n"
  end

  it "can be redefined and receive a frozen string as argument" do
    called = false
    runner = Object.new

    runner.singleton_class.define_method(:`) do |str|
      called = true

      str.should == "test command"
      str.frozen?.should == true
    end

    runner.instance_exec do
      %x{test command}
    end

    called.should == true
  end

  it "the argument isn't frozen if it contains interpolation" do
    called = false
    runner = Object.new

    runner.singleton_class.define_method(:`) do |str|
      called = true

      str.should == "test command"
      str.frozen?.should == false
      str << "mutated"
    end

    2.times do
      runner.instance_exec do
        %x{test #{:command}}
      end
    end

    called.should == true
  end
end
