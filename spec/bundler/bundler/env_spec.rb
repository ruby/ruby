# frozen_string_literal: true

require "openssl"
require "bundler/settings"

RSpec.describe Bundler::Env do
  let(:git_proxy_stub) { Bundler::Source::Git::GitProxy.new(nil, nil, nil) }

  describe "#report" do
    it "prints the environment" do
      out = described_class.report

      expect(out).to include("Environment")
      expect(out).to include(Bundler::VERSION)
      expect(out).to include(Gem::VERSION)
      expect(out).to include(described_class.send(:ruby_version))
      expect(out).to include(described_class.send(:git_version))
      expect(out).to include(OpenSSL::OPENSSL_VERSION)
    end

    describe "rubygems paths" do
      it "prints gem home" do
        with_clear_paths("GEM_HOME", "/a/b/c") do
          out = described_class.report
          expect(out).to include("Gem Home    /a/b/c")
        end
      end

      it "prints gem path" do
        with_clear_paths("GEM_PATH", "/a/b/c#{File::PATH_SEPARATOR}d/e/f") do
          out = described_class.report
          expect(out).to include("Gem Path    /a/b/c#{File::PATH_SEPARATOR}d/e/f")
        end
      end

      it "prints user home" do
        with_clear_paths("HOME", "/a/b/c") do
          out = described_class.report
          expect(out).to include("User Home   /a/b/c")
        end
      end

      it "prints user path" do
        if Gem::VERSION >= "3.1.0.pre.1"
          allow(Gem).to receive(:data_home) { "/a/b/c/.local/share" }
          out = described_class.report
          expect(out).to include("User Path   /a/b/c/.local/share/gem")
        else
          with_clear_paths("HOME", "/a/b/c") do
            out = described_class.report
            expect(out).to include("User Path   /a/b/c/.gem")
          end
        end
      end

      it "prints bin dir" do
        with_clear_paths("GEM_HOME", "/a/b/c") do
          out = described_class.report
          expect(out).to include("Bin Dir     /a/b/c/bin")
        end
      end

    private

      def with_clear_paths(env_var, env_value)
        old_env_var = ENV[env_var]
        ENV[env_var] = env_value
        Gem.clear_paths
        yield
      ensure
        ENV[env_var] = old_env_var
      end
    end

    context "when there is a Gemfile and a lockfile and print_gemfile is true" do
      before do
        gemfile "gem 'rack', '1.0.0'"

        lockfile <<-L
          GEM
            remote: #{file_uri_for(gem_repo1)}/
            specs:
              rack (1.0.0)

          DEPENDENCIES
            rack

          BUNDLED WITH
             1.10.0
        L
      end

      let(:output) { described_class.report(:print_gemfile => true) }

      it "prints the Gemfile" do
        expect(output).to include("Gemfile")
        expect(output).to include("'rack', '1.0.0'")
      end

      it "prints the lockfile" do
        expect(output).to include("Gemfile.lock")
        expect(output).to include("rack (1.0.0)")
      end
    end

    context "when there no Gemfile and print_gemfile is true" do
      let(:output) { described_class.report(:print_gemfile => true) }

      it "prints the environment" do
        expect(output).to start_with("## Environment")
      end
    end

    context "when Gemfile contains a gemspec and print_gemspecs is true" do
      let(:gemspec) do
        strip_whitespace(<<-GEMSPEC)
          Gem::Specification.new do |gem|
            gem.name = "foo"
            gem.author = "Fumofu"
          end
        GEMSPEC
      end

      before do
        gemfile("gemspec")

        File.open(bundled_app.join("foo.gemspec"), "wb") do |f|
          f.write(gemspec)
        end
      end

      it "prints the gemspec" do
        output = described_class.report(:print_gemspecs => true)

        expect(output).to include("foo.gemspec")
        expect(output).to include(gemspec)
      end
    end

    context "when eval_gemfile is used" do
      it "prints all gemfiles" do
        create_file "other/Gemfile-other", "gem 'rack'"
        create_file "other/Gemfile", "eval_gemfile 'Gemfile-other'"
        create_file "Gemfile-alt", <<-G
          source "#{file_uri_for(gem_repo1)}"
          eval_gemfile "other/Gemfile"
        G
        gemfile "eval_gemfile #{File.expand_path("Gemfile-alt").dump}"

        output = described_class.report(:print_gemspecs => true)
        expect(output).to include(strip_whitespace(<<-ENV))
          ## Gemfile

          ### Gemfile

          ```ruby
          eval_gemfile #{File.expand_path("Gemfile-alt").dump}
          ```

          ### Gemfile-alt

          ```ruby
          source "#{file_uri_for(gem_repo1)}"
          eval_gemfile "other/Gemfile"
          ```

          ### other/Gemfile

          ```ruby
          eval_gemfile 'Gemfile-other'
          ```

          ### other/Gemfile-other

          ```ruby
          gem 'rack'
          ```

          ### Gemfile.lock

          ```
          <No #{bundled_app("Gemfile.lock")} found>
          ```
        ENV
      end
    end

    context "when the git version is OS specific" do
      it "includes OS specific information with the version number" do
        expect(git_proxy_stub).to receive(:git).with("--version").
          and_return("git version 1.2.3 (Apple Git-BS)")
        expect(Bundler::Source::Git::GitProxy).to receive(:new).and_return(git_proxy_stub)

        expect(described_class.report).to include("Git         1.2.3 (Apple Git-BS)")
      end
    end
  end

  describe ".version_of" do
    let(:parsed_version) { described_class.send(:version_of, "ruby") }

    it "strips version of new line characters" do
      expect(parsed_version).to_not end_with("\n")
    end
  end
end
