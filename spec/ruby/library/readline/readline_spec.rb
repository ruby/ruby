require_relative 'spec_helper'

with_feature :readline do
  describe "Readline.readline" do
    before :each do
      @file = tmp('readline')
      @out = tmp('out.txt')
      touch(@file) { |f|
        f.puts "test"
      }
      @options = { options: "-rreadline", args: [@out, "< #{@file}"] }
    end

    after :each do
      rm_r @file, @out
    end

    # Somehow those specs block on Windows
    platform_is_not :windows do
      it "returns the input string" do
        ruby_exe('File.write ARGV[0], Readline.readline', @options)
        File.read(@out).should == "test"
      end
    end
  end
end
