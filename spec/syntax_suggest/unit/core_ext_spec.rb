require_relative "../spec_helper"

module SyntaxSuggest
  RSpec.describe "Core extension" do
    it "SyntaxError monkepatch ensures there is a newline to the end of the file" do
      skip if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.2")

      Dir.mktmpdir do |dir|
        tmpdir = Pathname(dir)
        file = tmpdir.join("file.rb")
        file.write(<<~'EOM'.strip)
          print 'no newline
        EOM

        core_ext_file = lib_dir.join("syntax_suggest").join("core_ext")
        require_relative core_ext_file

        original_message = "blerg"
        error = SyntaxError.new(original_message)
        def error.set_tmp_path_for_testing=(path)
          @tmp_path_for_testing = path
        end
        error.set_tmp_path_for_testing = file
        def error.path
          @tmp_path_for_testing
        end

        detailed = error.detailed_message(highlight: false, syntax_suggest: true)
        expect(detailed).to include("'no newline\n#{original_message}")
        expect(detailed).to_not include("print 'no newline#{original_message}")
      end
    end
  end
end
