require_relative '../spec_helper'

describe "The --enable and --disable flags" do

  it "can be used with gems" do
    ruby_exe("p defined?(Gem)", options: "--enable=gems").chomp.should == "\"constant\""
    ruby_exe("p defined?(Gem)", options: "--disable=gems").chomp.should == "nil"
    ruby_exe("p defined?(Gem)", options: "--enable-gems").chomp.should == "\"constant\""
    ruby_exe("p defined?(Gem)", options: "--disable-gems").chomp.should == "nil"
  end

  it "can be used with gem" do
    ruby_exe("p defined?(Gem)", options: "--enable=gem").chomp.should == "\"constant\""
    ruby_exe("p defined?(Gem)", options: "--disable=gem").chomp.should == "nil"
    ruby_exe("p defined?(Gem)", options: "--enable-gem").chomp.should == "\"constant\""
    ruby_exe("p defined?(Gem)", options: "--disable-gem").chomp.should == "nil"
  end

  it "can be used with did_you_mean" do
    ruby_exe("p defined?(DidYouMean)", options: "--enable=did_you_mean").chomp.should == "\"constant\""
    ruby_exe("p defined?(DidYouMean)", options: "--disable=did_you_mean").chomp.should == "nil"
    ruby_exe("p defined?(DidYouMean)", options: "--enable-did_you_mean").chomp.should == "\"constant\""
    ruby_exe("p defined?(DidYouMean)", options: "--disable-did_you_mean").chomp.should == "nil"
  end

  it "can be used with rubyopt" do
    ruby_exe("p $VERBOSE", options: "--enable=rubyopt", env: {'RUBYOPT' => '-w'}).chomp.should == "true"
    ruby_exe("p $VERBOSE", options: "--disable=rubyopt", env: {'RUBYOPT' => '-w'}).chomp.should == "false"
    ruby_exe("p $VERBOSE", options: "--enable-rubyopt", env: {'RUBYOPT' => '-w'}).chomp.should == "true"
    ruby_exe("p $VERBOSE", options: "--disable-rubyopt", env: {'RUBYOPT' => '-w'}).chomp.should == "false"
  end

  it "can be used with frozen-string-literal" do
    ruby_exe("p 'foo'.frozen?", options: "--enable=frozen-string-literal").chomp.should == "true"
    ruby_exe("p 'foo'.frozen?", options: "--disable=frozen-string-literal").chomp.should == "false"
    ruby_exe("p 'foo'.frozen?", options: "--enable-frozen-string-literal").chomp.should == "true"
    ruby_exe("p 'foo'.frozen?", options: "--disable-frozen-string-literal").chomp.should == "false"
  end

  it "can be used with all for enable" do
    e = "p [defined?(Gem), defined?(DidYouMean), $VERBOSE, 'foo'.frozen?]"
    env = {'RUBYOPT' => '-w'}
    # Use a single variant here because it can be quite slow as it might enable jit, etc
    ruby_exe(e, options: "--enable-all", env: env).chomp.should == "[\"constant\", \"constant\", true, true]"
  end

  it "can be used with all for disable" do
    e = "p [defined?(Gem), defined?(DidYouMean), $VERBOSE, 'foo'.frozen?]"
    env = {'RUBYOPT' => '-w'}
    ruby_exe(e, options: "--disable=all", env: env).chomp.should == "[nil, nil, false, false]"
    ruby_exe(e, options: "--disable-all", env: env).chomp.should == "[nil, nil, false, false]"
  end

  it "prints a warning for unknown features" do
    ruby_exe("p 14", options: "--enable=ruby-spec-feature-does-not-exist 2>&1").chomp.should include('warning: unknown argument for --enable')
    ruby_exe("p 14", options: "--disable=ruby-spec-feature-does-not-exist 2>&1").chomp.should include('warning: unknown argument for --disable')
    ruby_exe("p 14", options: "--enable-ruby-spec-feature-does-not-exist 2>&1").chomp.should include('warning: unknown argument for --enable')
    ruby_exe("p 14", options: "--disable-ruby-spec-feature-does-not-exist 2>&1").chomp.should include('warning: unknown argument for --disable')
  end

end
