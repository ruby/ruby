require_relative '../spec_helper'

describe "The --enable-frozen-string-literal flag causes string literals to" do

  it "produce the same object each time" do
    ruby_exe(fixture(__FILE__, "freeze_flag_one_literal.rb"), options: "--enable-frozen-string-literal").chomp.should == "true"
  end

  it "produce the same object for literals with the same content" do
    ruby_exe(fixture(__FILE__, "freeze_flag_two_literals.rb"), options: "--enable-frozen-string-literal").chomp.should == "true"
  end

  it "produce the same object for literals with the same content in different files" do
    ruby_exe(fixture(__FILE__, "freeze_flag_across_files.rb"), options: "--enable-frozen-string-literal").chomp.should == "true"
  end

  it "produce different objects for literals with the same content in different files if they have different encodings" do
    ruby_exe(fixture(__FILE__, "freeze_flag_across_files_diff_enc.rb"), options: "--enable-frozen-string-literal").chomp.should == "true"
  end
end

describe "The --disable-frozen-string-literal flag causes string literals to" do

  it "produce a different object each time" do
    ruby_exe(fixture(__FILE__, "freeze_flag_one_literal.rb"), options: "--disable-frozen-string-literal").chomp.should == "false"
  end

end

describe "With neither --enable-frozen-string-literal nor --disable-frozen-string-literal flag set" do
  before do
    # disable --enable-frozen-string-literal and --disable-frozen-string-literal passed in $RUBYOPT
    @rubyopt = ENV["RUBYOPT"]
    ENV["RUBYOPT"] = ""
  end

  after do
    ENV["RUBYOPT"] = @rubyopt
  end

  it "produce a different object each time" do
    ruby_exe(fixture(__FILE__, "freeze_flag_one_literal.rb")).chomp.should == "false"
  end

  it "if file has no frozen_string_literal comment produce different mutable strings each time" do
    ruby_exe(fixture(__FILE__, "string_literal_raw.rb")).chomp.should == "frozen:false interned:false"
  end

  it "if file has frozen_string_literal:true comment produce same frozen strings each time" do
    ruby_exe(fixture(__FILE__, "string_literal_frozen_comment.rb")).chomp.should == "frozen:true interned:true"
  end

  it "if file has frozen_string_literal:false comment produce different mutable strings each time" do
    ruby_exe(fixture(__FILE__, "string_literal_mutable_comment.rb")).chomp.should == "frozen:false interned:false"
  end
end

describe "The --debug flag produces" do
  it "debugging info on attempted frozen string modification" do
    error_str = ruby_exe(fixture(__FILE__, 'debug_info.rb'), options: '--enable-frozen-string-literal --debug',  args: "2>&1")
    error_str.should include("can't modify frozen String")
    error_str.should include("created at")
    error_str.should include("command_line/fixtures/debug_info.rb:1")
  end

  guard -> { ruby_version_is "3.4" and !"test".frozen? } do
    it "debugging info on mutating chilled string" do
      error_str = ruby_exe(fixture(__FILE__, 'debug_info.rb'), options: '-w --debug',  args: "2>&1")
      error_str.should include("literal string will be frozen in the future")
      error_str.should include("the string was created here")
      error_str.should include("command_line/fixtures/debug_info.rb:1")
    end
  end
end
