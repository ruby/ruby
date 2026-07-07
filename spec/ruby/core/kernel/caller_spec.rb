require_relative '../../spec_helper'
require_relative 'fixtures/caller'

describe 'Kernel#caller' do
  it 'is a private method' do
    Kernel.private_instance_methods(false).should.include?(:caller)
  end

  it 'returns an Array of caller locations' do
    KernelSpecs::CallerTest.locations.should_not.empty?
  end

  it 'returns an Array of caller locations using a custom offset' do
    locations = KernelSpecs::CallerTest.locations(2)

    locations[0].should =~ %r{runner/mspec.rb}
  end

  it 'returns an Array of caller locations using a custom limit' do
    locations = KernelSpecs::CallerTest.locations(1, 1)

    locations.length.should == 1
  end

  it 'returns an Array of caller locations using a range' do
    locations = KernelSpecs::CallerTest.locations(1..1)

    locations.length.should == 1
  end

  it 'returns the locations as String instances' do
    locations = KernelSpecs::CallerTest.locations
    line      = __LINE__ - 1

    locations[0].should.include?("#{__FILE__}:#{line}:in")
  end

  it "returns an Array with the block given to #at_exit at the base of the stack" do
    path = fixture(__FILE__, "caller_at_exit.rb")
    lines = ruby_exe(path).lines
    lines.size.should == 2
    lines[0].should =~ /\A#{path}:6:in [`'](?:Object#)?foo'\n\z/
    lines[1].should =~ /\A#{path}:2:in [`']block in <main>'\n\z/
  end

  it "raises for negative start" do
    -> { caller(-1) }.should.raise(ArgumentError, "negative level (-1)")
  end

  it "raises for negative length" do
    -> { caller(0, -1) }.should.raise(ArgumentError, "negative size (-1)")
  end

  it "can be called with `nil` length" do
    caller(0, nil).should == caller(0)
  end

  it "can be called with a range" do
    locations1 = caller(0)
    locations2 = caller(2..4)
    locations1[2..4].should == locations2
  end

  it "works with endless ranges" do
    locations1 = KernelSpecs::CallerTest.locations(0)
    locations2 = KernelSpecs::CallerTest.locations(eval("(2..)"))
    locations2.should == locations1[2..-1]
  end

  it "works with beginless ranges" do
    locations1 = KernelSpecs::CallerTest.locations(0)
    locations2 = KernelSpecs::CallerTest.locations((..5))
    locations2[eval("(2..)")].should == locations1[(..5)][eval("(2..)")]
  end

  it "can be called with a range whose end is negative" do
    locations1 = caller(0)
    locations2 = caller(2..-1)
    locations3 = caller(2..-2)
    locations1[2..-1].should == locations2
    locations1[2..-2].should == locations3
  end

  it "must return nil if omitting more locations than available" do
    caller(100).should == nil
    caller(100..-1).should == nil
  end

  it "must return [] if omitting exactly the number of locations available" do
    omit = caller(0).length
    caller(omit).should == []
  end

  it "must return the same locations when called with 1..-1 and when called with no arguments" do
    caller.should == caller(1..-1)
  end

  it "coerces the arguments to integers" do
    caller(1.1, 1.1).should == caller(1, 1)
    caller(1.1..1.1).should == caller(1..1)
  end

  guard -> { Kernel.instance_method(:tap).source_location } do
    ruby_version_is ""..."3.4" do
      it "includes core library methods defined in Ruby" do
        file, line = Kernel.instance_method(:tap).source_location
        file.should.start_with?('<internal:')

        loc = nil
        tap { loc = caller(1, 1)[0] }
        loc.should =~ /\A<internal:.*in `tap'\z/
      end
    end

    ruby_version_is "3.4"..."4.0" do
      it "includes core library methods defined in Ruby" do
        file, line = Kernel.instance_method(:tap).source_location
        file.should.start_with?('<internal:')

        loc = nil
        tap { loc = caller(1, 1)[0] }
        loc.should =~ /\A<internal:.*in 'Kernel#tap'\z/
      end
    end

    ruby_version_is "4.0" do
      it "does not include core library methods defined in Ruby" do
        file, line = Kernel.instance_method(:tap).source_location
        file.should.start_with?('<internal:')

        loc = nil
        tap { loc = caller(1, 1)[0] }
        # CRuby hides the file which defines the method: https://bugs.ruby-lang.org/issues/20968
        loc.should =~ /\A(<internal:|#{__FILE__}:).*in 'Kernel#tap'\z/
      end
    end
  end
end

describe "Kernel.caller" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:caller)
  end
end
