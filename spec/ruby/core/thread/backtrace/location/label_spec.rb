require_relative '../../../../spec_helper'
require_relative 'fixtures/classes'

describe 'Thread::Backtrace::Location#label' do
  it 'returns the base label of the call frame' do
    ThreadBacktraceLocationSpecs.locations[0].label.should include('<top (required)>')
  end

  it 'returns the method name for a method location' do
    ThreadBacktraceLocationSpecs.method_location[0].label.should =~ /\A(?:ThreadBacktraceLocationSpecs\.)?method_location\z/
  end

  it 'returns the block name for a block location' do
    ThreadBacktraceLocationSpecs.block_location[0].label.should =~ /\Ablock in (?:ThreadBacktraceLocationSpecs\.)?block_location\z/
  end

  it 'returns the module name for a module location' do
    ThreadBacktraceLocationSpecs::MODULE_LOCATION[0].label.should include "ThreadBacktraceLocationSpecs"
  end

  it 'includes the nesting level of a block as part of the location label' do
    first_level_location, second_level_location, third_level_location =
      ThreadBacktraceLocationSpecs.locations_inside_nested_blocks

    first_level_location.label.should =~ /\Ablock in (?:ThreadBacktraceLocationSpecs\.)?locations_inside_nested_blocks\z/
    second_level_location.label.should =~ /\Ablock \(2 levels\) in (?:ThreadBacktraceLocationSpecs\.)?locations_inside_nested_blocks\z/
    third_level_location.label.should =~ /\Ablock \(3 levels\) in (?:ThreadBacktraceLocationSpecs\.)?locations_inside_nested_blocks\z/
  end

  it 'sets the location label for a top-level block differently depending on it being in the main file or a required file' do
    path = fixture(__FILE__, "locations_in_main.rb")
    main_label, required_label = ruby_exe(path).lines

    main_label.should == "block in <main>\n"
    required_label.should == "block in <top (required)>\n"
  end
end
