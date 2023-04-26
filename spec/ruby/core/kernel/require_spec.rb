require_relative '../../spec_helper'
require_relative '../../fixtures/code_loading'
require_relative 'shared/require'

describe "Kernel#require" do
  before :each do
    CodeLoadingSpecs.spec_setup
  end

  after :each do
    CodeLoadingSpecs.spec_cleanup
  end

  # if this fails, update your rubygems
  it "is a private method" do
    Kernel.should have_private_instance_method(:require)
  end

  provided = %w[complex enumerator rational thread ruby2_keywords]
  ruby_version_is "3.1" do
    provided << "fiber"
  end

  it "#{provided.join(', ')} are already required" do
    out = ruby_exe("puts $LOADED_FEATURES", options: '--disable-gems --disable-did-you-mean')
    features = out.lines.map { |line| File.basename(line.chomp, '.*') }

    # Ignore CRuby internals
    features -= %w[encdb transdb windows_1252]
    features.reject! { |feature| feature.end_with?('-fake') }

    features.sort.should == provided.sort

    code = provided.map { |f| "puts require #{f.inspect}\n" }.join
    required = ruby_exe(code, options: '--disable-gems')
    required.should == "false\n" * provided.size
  end

  it_behaves_like :kernel_require_basic, :require, CodeLoadingSpecs::Method.new
  it_behaves_like :kernel_require, :require, CodeLoadingSpecs::Method.new
end

describe "Kernel.require" do
  before :each do
    CodeLoadingSpecs.spec_setup
  end

  after :each do
    CodeLoadingSpecs.spec_cleanup
  end

  it_behaves_like :kernel_require_basic, :require, Kernel
  it_behaves_like :kernel_require, :require, Kernel
end
