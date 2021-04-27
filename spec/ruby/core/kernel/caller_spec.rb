require_relative '../../spec_helper'
require_relative 'fixtures/caller'

describe 'Kernel#caller' do
  it 'is a private method' do
    Kernel.should have_private_instance_method(:caller)
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

    locations[0].should include("#{__FILE__}:#{line}:in")
  end

  it "returns an Array with the block given to #at_exit at the base of the stack" do
    path = fixture(__FILE__, "caller_at_exit.rb")
    lines = ruby_exe(path).lines
    lines.should == [
      "#{path}:6:in `foo'\n",
      "#{path}:2:in `block in <main>'\n"
    ]
  end

  ruby_version_is "2.6" do
    it "works with endless ranges" do
      locations1 = KernelSpecs::CallerTest.locations(0)
      locations2 = KernelSpecs::CallerTest.locations(eval("(2..)"))
      locations2.map(&:to_s).should == locations1[2..-1].map(&:to_s)
    end
  end

  ruby_version_is "2.7" do
    it "works with beginless ranges" do
      locations1 = KernelSpecs::CallerTest.locations(0)
      locations2 = KernelSpecs::CallerTest.locations(eval("(..5)"))
      locations2.map(&:to_s)[eval("(2..)")].should == locations1[eval("(..5)")].map(&:to_s)[eval("(2..)")]
    end
  end

  guard -> { Kernel.instance_method(:tap).source_location } do
    it "includes core library methods defined in Ruby" do
      file, line = Kernel.instance_method(:tap).source_location
      file.should.start_with?('<internal:')

      loc = nil
      tap { loc = caller(1, 1)[0] }
      loc.should.end_with? "in `tap'"
      loc.should.start_with? "<internal:"
    end
  end
end
