# frozen_string_literal: true

require_relative "../spec_helper"

module SyntaxSuggest
  ruby = ENV.fetch("RUBY", "ruby")
  RSpec.describe "Requires with ruby cli" do
    it "namespaces all monkeypatched methods" do
      Dir.mktmpdir do |dir|
        tmpdir = Pathname(dir)
        script = tmpdir.join("script.rb")
        script.write <<~EOM
          puts Kernel.private_methods
        EOM

        syntax_suggest_methods_file = tmpdir.join("syntax_suggest_methods.txt")
        api_only_methods_file = tmpdir.join("api_only_methods.txt")
        kernel_methods_file = tmpdir.join("kernel_methods.txt")

        d_pid = Process.spawn("#{ruby} -I#{lib_dir} -rsyntax_suggest #{script} 2>&1 > #{syntax_suggest_methods_file}")
        k_pid = Process.spawn("#{ruby} #{script} 2>&1 >> #{kernel_methods_file}")
        r_pid = Process.spawn("#{ruby} -I#{lib_dir} -rsyntax_suggest/api #{script} 2>&1 > #{api_only_methods_file}")

        Process.wait(k_pid)
        Process.wait(d_pid)
        Process.wait(r_pid)

        kernel_methods_array = kernel_methods_file.read.strip.lines.map(&:strip)
        syntax_suggest_methods_array = syntax_suggest_methods_file.read.strip.lines.map(&:strip)
        api_only_methods_array = api_only_methods_file.read.strip.lines.map(&:strip)

        # In ruby 3.1.0-preview1 the `timeout` file is already required
        # we can remove it if it exists to normalize the output for
        # all ruby versions
        [syntax_suggest_methods_array, kernel_methods_array, api_only_methods_array].each do |array|
          array.delete("timeout")
        end

        methods = (syntax_suggest_methods_array - kernel_methods_array).sort
        if methods.any?
          expect(methods).to eq(["syntax_suggest_original_load", "syntax_suggest_original_require", "syntax_suggest_original_require_relative"])
        end

        methods = (api_only_methods_array - kernel_methods_array).sort
        expect(methods).to eq([])
      end
    end

    # Since Ruby 3.2 includes syntax_suggest as a default gem, we might accidentally
    # be requiring the default gem instead of this library under test. Assert that's
    # not the case
    it "tests current version of syntax_suggest" do
      Dir.mktmpdir do |dir|
        tmpdir = Pathname(dir)
        script = tmpdir.join("script.rb")
        contents = <<~'EOM'
          puts "suggest_version is #{SyntaxSuggest::VERSION}"
        EOM
        script.write(contents)

        out = `#{ruby} -I#{lib_dir} -rsyntax_suggest/version #{script} 2>&1`

        expect(out).to include("suggest_version is #{SyntaxSuggest::VERSION}").once
      end
    end

    it "detects require error and adds a message with auto mode" do
      Dir.mktmpdir do |dir|
        tmpdir = Pathname(dir)
        script = tmpdir.join("script.rb")
        script.write <<~EOM
          describe "things" do
            it "blerg" do
            end

            it "flerg"
            end

            it "zlerg" do
            end
          end
        EOM

        require_rb = tmpdir.join("require.rb")
        require_rb.write <<~EOM
          load "#{script.expand_path}"
        EOM

        out = `#{ruby} -I#{lib_dir} -rsyntax_suggest #{require_rb} 2>&1`

        expect($?.success?).to be_falsey
        expect(out).to include('>  5    it "flerg"').once
      end
    end

    it "gem can be tested when executing on Ruby with default gem included" do
      skip if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.2")

      out = `#{ruby} -I#{lib_dir} -rsyntax_suggest -e "puts SyntaxError.instance_method(:detailed_message).source_location" 2>&1`

      expect($?.success?).to be_truthy
      expect(out).to include(lib_dir.join("syntax_suggest").join("core_ext.rb").to_s).once
    end

    it "annotates a syntax error in Ruby 3.2+ when require is not used" do
      skip if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.2")

      Dir.mktmpdir do |dir|
        tmpdir = Pathname(dir)
        script = tmpdir.join("script.rb")
        script.write <<~EOM
          describe "things" do
            it "blerg" do
            end

            it "flerg"
            end

            it "zlerg" do
            end
          end
        EOM

        out = `#{ruby} -I#{lib_dir} -rsyntax_suggest #{script} 2>&1`

        expect($?.success?).to be_falsey
        expect(out).to include('>  5    it "flerg"').once
      end
    end

    it "does not load internals into memory if no syntax error" do
      Dir.mktmpdir do |dir|
        tmpdir = Pathname(dir)
        script = tmpdir.join("script.rb")
        script.write <<~EOM
          class Dog
          end

          if defined?(SyntaxSuggest::DEFAULT_VALUE)
            puts "SyntaxSuggest is loaded"
          else
            puts "SyntaxSuggest is NOT loaded"
          end
        EOM

        require_rb = tmpdir.join("require.rb")
        require_rb.write <<~EOM
          load "#{script.expand_path}"
        EOM

        out = `#{ruby} -I#{lib_dir} -rsyntax_suggest #{require_rb} 2>&1`

        expect($?.success?).to be_truthy
        expect(out).to include("SyntaxSuggest is NOT loaded").once
      end
    end

    it "ignores eval" do
      Dir.mktmpdir do |dir|
        tmpdir = Pathname(dir)
        script = tmpdir.join("script.rb")
        script.write <<~EOM
          $stderr = STDOUT
          eval("def lol")
        EOM

        out = `#{ruby} -I#{lib_dir} -rsyntax_suggest #{script} 2>&1`

        expect($?.success?).to be_falsey
        expect(out).to match(/\(eval.*\):1/)

        expect(out).to_not include("SyntaxSuggest")
        expect(out).to_not include("Could not find filename")
      end
    end

    it "does not say 'syntax ok' when a syntax error fires" do
      Dir.mktmpdir do |dir|
        tmpdir = Pathname(dir)
        script = tmpdir.join("script.rb")
        script.write <<~EOM
          break
        EOM

        out = `#{ruby} -I#{lib_dir} -rsyntax_suggest -e "require_relative '#{script}'" 2>&1`

        expect($?.success?).to be_falsey
        expect(out.downcase).to_not include("syntax ok")
        expect(out).to include("Invalid break")
      end
    end
  end
end
