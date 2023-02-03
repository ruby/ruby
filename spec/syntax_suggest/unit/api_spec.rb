# frozen_string_literal: true

require_relative "../spec_helper"
begin
  require "ruby-prof"
rescue LoadError
end

module SyntaxSuggest
  RSpec.describe "Top level SyntaxSuggest api" do
    it "has a `handle_error` interface" do
      fake_error = Object.new
      def fake_error.message
        "#{__FILE__}:216: unterminated string meets end of file "
      end

      def fake_error.is_a?(v)
        true
      end

      io = StringIO.new
      SyntaxSuggest.handle_error(
        fake_error,
        re_raise: false,
        io: io
      )

      expect(io.string.strip).to eq("")
    end

    it "raises original error with warning if a non-syntax error is passed" do
      error = NameError.new("blerg")
      io = StringIO.new
      expect {
        SyntaxSuggest.handle_error(
          error,
          re_raise: false,
          io: io
        )
      }.to raise_error { |e|
        expect(io.string).to include("Must pass a SyntaxError")
        expect(e).to eq(error)
      }
    end

    it "raises original error with warning if file is not found" do
      fake_error = SyntaxError.new
      def fake_error.message
        "#does/not/exist/lol/doesnotexist:216: unterminated string meets end of file "
      end

      io = StringIO.new
      expect {
        SyntaxSuggest.handle_error(
          fake_error,
          re_raise: false,
          io: io
        )
      }.to raise_error { |e|
        expect(io.string).to include("Could not find filename")
        expect(e).to eq(fake_error)
      }
    end

    it "respects highlight API" do
      skip if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.2")

      core_ext_file = lib_dir.join("syntax_suggest").join("core_ext.rb")
      require_relative core_ext_file

      error_klass = Class.new do
        def path
          fixtures_dir.join("this_project_extra_def.rb.txt")
        end

        def detailed_message(**kwargs)
          "error"
        end
      end
      error_klass.prepend(SyntaxSuggest.module_for_detailed_message)
      error = error_klass.new

      expect(error.detailed_message(highlight: true)).to include(SyntaxSuggest::DisplayCodeWithLineNumbers::TERMINAL_HIGHLIGHT)
      expect(error.detailed_message(highlight: false)).to_not include(SyntaxSuggest::DisplayCodeWithLineNumbers::TERMINAL_HIGHLIGHT)
    end

    it "can be disabled via falsey kwarg" do
      skip if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.2")

      core_ext_file = lib_dir.join("syntax_suggest").join("core_ext.rb")
      require_relative core_ext_file

      error_klass = Class.new do
        def path
          fixtures_dir.join("this_project_extra_def.rb.txt")
        end

        def detailed_message(**kwargs)
          "error"
        end
      end
      error_klass.prepend(SyntaxSuggest.module_for_detailed_message)
      error = error_klass.new

      expect(error.detailed_message(syntax_suggest: true)).to_not eq(error.detailed_message(syntax_suggest: false))
    end
  end
end
