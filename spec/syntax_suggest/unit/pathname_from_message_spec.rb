# frozen_string_literal: true

require_relative "../spec_helper"

module SyntaxSuggest
  RSpec.describe "PathnameFromMessage" do
    it "handles filenames with colons in them" do
      Dir.mktmpdir do |dir|
        dir = Pathname(dir)

        file = dir.join("scr:atch.rb").tap { |p| FileUtils.touch(p) }

        message = "#{file}:2:in `require_relative': /private/tmp/bad.rb:1: syntax error, unexpected `end' (SyntaxError)"
        file = PathnameFromMessage.new(message).call.name

        expect(file).to be_truthy
      end
    end

    it "checks if the file exists" do
      Dir.mktmpdir do |dir|
        dir = Pathname(dir)

        file = dir.join("scratch.rb")
        # No touch, file does not exist
        expect(file.exist?).to be_falsey

        message = "#{file}:2:in `require_relative': /private/tmp/bad.rb:1: syntax error, unexpected `end' (SyntaxError)"
        io = StringIO.new
        file = PathnameFromMessage.new(message, io: io).call.name

        expect(io.string).to include(file.to_s)
        expect(file).to be_falsey
      end
    end

    it "does not output error message on syntax error inside of an (eval)" do
      message = "(eval):1: invalid multibyte char (UTF-8) (SyntaxError)\n"
      io = StringIO.new
      file = PathnameFromMessage.new(message, io: io).call.name

      expect(io.string).to eq("")
      expect(file).to be_falsey
    end

    it "does not output error message on syntax error inside of streamed code" do
      # An example of streamed code is: $ echo "def foo" | ruby
      message = "-:1: syntax error, unexpected end-of-input\n"
      io = StringIO.new
      file = PathnameFromMessage.new(message, io: io).call.name

      expect(io.string).to eq("")
      expect(file).to be_falsey
    end
  end
end
