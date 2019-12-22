# frozen_string_literal: true

require "bundler"
require "tmpdir"

RSpec.describe Bundler do
  describe "#load_gemspec_uncached" do
    let(:app_gemspec_path) { tmp("test.gemspec") }
    subject { Bundler.load_gemspec_uncached(app_gemspec_path) }

    context "with incorrect YAML file" do
      before do
        File.open(app_gemspec_path, "wb") do |f|
          f.write strip_whitespace(<<-GEMSPEC)
            ---
              {:!00 ao=gu\g1= 7~f
          GEMSPEC
        end
      end

      it "catches YAML syntax errors" do
        expect { subject }.to raise_error(Bundler::GemspecError, /error while loading `test.gemspec`/)
      end

      context "on Rubies with a settable YAML engine", :if => defined?(YAML::ENGINE) do
        context "with Syck as YAML::Engine" do
          it "raises a GemspecError after YAML load throws ArgumentError" do
            orig_yamler = YAML::ENGINE.yamler
            YAML::ENGINE.yamler = "syck"

            expect { subject }.to raise_error(Bundler::GemspecError)

            YAML::ENGINE.yamler = orig_yamler
          end
        end

        context "with Psych as YAML::Engine" do
          it "raises a GemspecError after YAML load throws Psych::SyntaxError" do
            orig_yamler = YAML::ENGINE.yamler
            YAML::ENGINE.yamler = "psych"

            expect { subject }.to raise_error(Bundler::GemspecError)

            YAML::ENGINE.yamler = orig_yamler
          end
        end
      end
    end

    context "with correct YAML file", :if => defined?(Encoding) do
      it "can load a gemspec with unicode characters with default ruby encoding" do
        # spec_helper forces the external encoding to UTF-8 but that's not the
        # default until Ruby 2.0
        verbose = $VERBOSE
        $VERBOSE = false
        encoding = Encoding.default_external
        Encoding.default_external = "ASCII"
        $VERBOSE = verbose

        File.open(app_gemspec_path, "wb") do |file|
          file.puts <<-GEMSPEC.gsub(/^\s+/, "")
            # -*- encoding: utf-8 -*-
            Gem::Specification.new do |gem|
              gem.author = "André the Giant"
            end
          GEMSPEC
        end

        expect(subject.author).to eq("André the Giant")

        verbose = $VERBOSE
        $VERBOSE = false
        Encoding.default_external = encoding
        $VERBOSE = verbose
      end
    end

    it "sets loaded_from" do
      app_gemspec_path.open("w") do |f|
        f.puts <<-GEMSPEC
          Gem::Specification.new do |gem|
            gem.name = "validated"
          end
        GEMSPEC
      end

      expect(subject.loaded_from).to eq(app_gemspec_path.expand_path.to_s)
    end

    context "validate is true" do
      subject { Bundler.load_gemspec_uncached(app_gemspec_path, true) }

      it "validates the specification" do
        app_gemspec_path.open("w") do |f|
          f.puts <<-GEMSPEC
            Gem::Specification.new do |gem|
              gem.name = "validated"
            end
          GEMSPEC
        end
        expect(Bundler.rubygems).to receive(:validate).with have_attributes(:name => "validated")
        subject
      end
    end

    context "with gemspec containing local variables" do
      before do
        File.open(app_gemspec_path, "wb") do |f|
          f.write strip_whitespace(<<-GEMSPEC)
            must_not_leak = true
            Gem::Specification.new do |gem|
              gem.name = "leak check"
            end
          GEMSPEC
        end
      end

      it "should not pollute the TOPLEVEL_BINDING" do
        subject
        expect(TOPLEVEL_BINDING.eval("local_variables")).to_not include(:must_not_leak)
      end
    end
  end

  describe "#which" do
    let(:executable) { "executable" }
    let(:path) { %w[/a /b c ../d /e] }
    let(:expected) { "executable" }

    before do
      ENV["PATH"] = path.join(File::PATH_SEPARATOR)

      allow(File).to receive(:file?).and_return(false)
      allow(File).to receive(:executable?).and_return(false)
      if expected
        expect(File).to receive(:file?).with(expected).and_return(true)
        expect(File).to receive(:executable?).with(expected).and_return(true)
      end
    end

    subject { described_class.which(executable) }

    shared_examples_for "it returns the correct executable" do
      it "returns the expected file" do
        expect(subject).to eq(expected)
      end
    end

    it_behaves_like "it returns the correct executable"

    context "when the executable in inside a quoted path" do
      let(:expected) { "/e/executable" }
      it_behaves_like "it returns the correct executable"
    end

    context "when the executable is not found" do
      let(:expected) { nil }
      it_behaves_like "it returns the correct executable"
    end
  end

  describe "configuration" do
    context "disable_shared_gems" do
      it "should unset GEM_PATH with empty string" do
        env = {}
        expect(Bundler).to receive(:use_system_gems?).and_return(false)
        Bundler.send(:configure_gem_path, env)
        expect(env.keys).to include("GEM_PATH")
        expect(env["GEM_PATH"]).to eq ""
      end
    end
  end

  describe "#rm_rf" do
    context "the directory is world writable" do
      let(:bundler_ui) { Bundler.ui }
      it "should raise a friendly error" do
        allow(File).to receive(:exist?).and_return(true)
        allow(::Bundler::FileUtils).to receive(:remove_entry_secure).and_raise(ArgumentError)
        allow(File).to receive(:world_writable?).and_return(true)
        message = <<EOF
It is a security vulnerability to allow your home directory to be world-writable, and bundler can not continue.
You should probably consider fixing this issue by running `chmod o-w ~` on *nix.
Please refer to https://ruby-doc.org/stdlib-2.1.2/libdoc/fileutils/rdoc/FileUtils.html#method-c-remove_entry_secure for details.
EOF
        expect(bundler_ui).to receive(:warn).with(message)
        expect { Bundler.send(:rm_rf, bundled_app) }.to raise_error(Bundler::PathError)
      end
    end
  end

  describe "#mkdir_p" do
    it "creates a folder at the given path" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      Bundler.mkdir_p(bundled_app.join("foo", "bar"))
      expect(bundled_app.join("foo", "bar")).to exist
    end

    context "when mkdir_p requires sudo" do
      it "creates a new folder using sudo" do
        expect(Bundler).to receive(:requires_sudo?).and_return(true)
        expect(Bundler).to receive(:sudo).and_return true
        Bundler.mkdir_p(bundled_app.join("foo"))
      end
    end

    context "with :no_sudo option" do
      it "forces mkdir_p to not use sudo" do
        expect(Bundler).to receive(:requires_sudo?).and_return(true)
        expect(Bundler).to_not receive(:sudo)
        Bundler.mkdir_p(bundled_app.join("foo"), :no_sudo => true)
      end
    end
  end

  describe "#user_home" do
    context "home directory is set" do
      it "should return the user home" do
        path = "/home/oggy"
        allow(Bundler.rubygems).to receive(:user_home).and_return(path)
        allow(File).to receive(:directory?).with(path).and_return true
        allow(File).to receive(:writable?).with(path).and_return true
        expect(Bundler.user_home).to eq(Pathname(path))
      end

      context "is not a directory" do
        it "should issue a warning and return a temporary user home" do
          path = "/home/oggy"
          allow(Bundler.rubygems).to receive(:user_home).and_return(path)
          allow(File).to receive(:directory?).with(path).and_return false
          allow(Bundler).to receive(:tmp).and_return(Pathname.new("/tmp/trulyrandom"))
          message = <<EOF
`/home/oggy` is not a directory.
Bundler will use `/tmp/trulyrandom' as your home directory temporarily.
EOF
          expect(Bundler.ui).to receive(:warn).with(message)
          expect(Bundler.user_home).to eq(Pathname("/tmp/trulyrandom"))
        end
      end

      context "is not writable" do
        let(:path) { "/home/oggy" }
        let(:dotbundle) { "/home/oggy/.bundle" }

        it "should issue a warning and return a temporary user home" do
          allow(Bundler.rubygems).to receive(:user_home).and_return(path)
          allow(File).to receive(:directory?).with(path).and_return true
          allow(File).to receive(:writable?).with(path).and_return false
          allow(File).to receive(:directory?).with(dotbundle).and_return false
          allow(Bundler).to receive(:tmp).and_return(Pathname.new("/tmp/trulyrandom"))
          message = <<EOF
`/home/oggy` is not writable.
Bundler will use `/tmp/trulyrandom' as your home directory temporarily.
EOF
          expect(Bundler.ui).to receive(:warn).with(message)
          expect(Bundler.user_home).to eq(Pathname("/tmp/trulyrandom"))
        end

        context ".bundle exists and have correct permissions" do
          it "should return the user home" do
            allow(Bundler.rubygems).to receive(:user_home).and_return(path)
            allow(File).to receive(:directory?).with(path).and_return true
            allow(File).to receive(:writable?).with(path).and_return false
            allow(File).to receive(:directory?).with(dotbundle).and_return true
            allow(File).to receive(:writable?).with(dotbundle).and_return true
            expect(Bundler.user_home).to eq(Pathname(path))
          end
        end
      end
    end

    context "home directory is not set" do
      it "should issue warning and return a temporary user home" do
        allow(Bundler.rubygems).to receive(:user_home).and_return(nil)
        allow(Bundler).to receive(:tmp).and_return(Pathname.new("/tmp/trulyrandom"))
        message = <<EOF
Your home directory is not set.
Bundler will use `/tmp/trulyrandom' as your home directory temporarily.
EOF
        expect(Bundler.ui).to receive(:warn).with(message)
        expect(Bundler.user_home).to eq(Pathname("/tmp/trulyrandom"))
      end
    end
  end

  describe "#requires_sudo?" do
    let!(:tmpdir) { Dir.mktmpdir }
    let(:bundle_path) { Pathname("#{tmpdir}/bundle") }

    def clear_cached_requires_sudo
      return unless Bundler.instance_variable_defined?(:@requires_sudo_ran)
      Bundler.remove_instance_variable(:@requires_sudo_ran)
      Bundler.remove_instance_variable(:@requires_sudo)
    end

    before do
      clear_cached_requires_sudo
      allow(Bundler).to receive(:which).with("sudo").and_return("/usr/bin/sudo")
      allow(Bundler).to receive(:bundle_path).and_return(bundle_path)
    end

    after do
      FileUtils.rm_rf(tmpdir)
      clear_cached_requires_sudo
    end

    subject { Bundler.requires_sudo? }

    context "bundle_path doesn't exist" do
      it { should be false }

      context "and parent dir can't be written" do
        before do
          FileUtils.chmod(0o500, tmpdir)
        end

        it { should be true }
      end

      context "with unwritable files in a parent dir" do
        # Regression test for https://github.com/bundler/bundler/pull/6316
        # It doesn't matter if there are other unwritable files so long as
        # bundle_path can be created
        before do
          file = File.join(tmpdir, "unrelated_file")
          FileUtils.touch(file)
          FileUtils.chmod(0o400, file)
        end

        it { should be false }
      end
    end

    context "bundle_path exists" do
      before do
        FileUtils.mkdir_p(bundle_path)
      end

      it { should be false }

      context "and is unwritable" do
        before do
          FileUtils.chmod(0o500, bundle_path)
        end

        it { should be true }
      end
    end

    context "path writability" do
      before do
        FileUtils.mkdir_p("tmp/vendor/bundle")
        FileUtils.mkdir_p("tmp/vendor/bin_dir")
      end
      after do
        FileUtils.rm_rf("tmp/vendor/bundle")
        FileUtils.rm_rf("tmp/vendor/bin_dir")
      end
      context "writable paths" do
        it "should return false and display nothing" do
          allow(Bundler).to receive(:bundle_path).and_return(Pathname("tmp/vendor/bundle"))
          expect(Bundler.ui).to_not receive(:warn)
          expect(Bundler.requires_sudo?).to eq(false)
        end
      end
      context "unwritable paths" do
        before do
          FileUtils.touch("tmp/vendor/bundle/unwritable1.txt")
          FileUtils.touch("tmp/vendor/bundle/unwritable2.txt")
          FileUtils.touch("tmp/vendor/bin_dir/unwritable3.txt")
          FileUtils.chmod(0o400, "tmp/vendor/bundle/unwritable1.txt")
          FileUtils.chmod(0o400, "tmp/vendor/bundle/unwritable2.txt")
          FileUtils.chmod(0o400, "tmp/vendor/bin_dir/unwritable3.txt")
        end
        it "should return true and display warn message" do
          allow(Bundler).to receive(:bundle_path).and_return(Pathname("tmp/vendor/bundle"))
          bin_dir = Pathname("tmp/vendor/bin_dir/")

          # allow File#writable? to be called with args other than the stubbed on below
          allow(File).to receive(:writable?).and_call_original

          # fake make the directory unwritable
          allow(File).to receive(:writable?).with(bin_dir).and_return(false)
          allow(Bundler).to receive(:system_bindir).and_return(Pathname("tmp/vendor/bin_dir/"))
          message = <<-MESSAGE.chomp
Following files may not be writable, so sudo is needed:
  tmp/vendor/bin_dir/
  tmp/vendor/bundle/unwritable1.txt
  tmp/vendor/bundle/unwritable2.txt
MESSAGE
          expect(Bundler.ui).to receive(:warn).with(message)
          expect(Bundler.requires_sudo?).to eq(true)
        end
      end
    end
  end

  context "user cache dir" do
    let(:home_path)                  { Pathname.new(ENV["HOME"]) }

    let(:xdg_data_home)              { home_path.join(".local") }
    let(:xdg_cache_home)             { home_path.join(".cache") }
    let(:xdg_config_home)            { home_path.join(".config") }

    let(:bundle_user_home_default)   { home_path.join(".bundle") }
    let(:bundle_user_home_custom)    { xdg_data_home.join("bundle") }

    let(:bundle_user_cache_default)  { bundle_user_home_default.join("cache") }
    let(:bundle_user_cache_custom)   { xdg_cache_home.join("bundle") }

    let(:bundle_user_config_default) { bundle_user_home_default.join("config") }
    let(:bundle_user_config_custom)  { xdg_config_home.join("bundle") }

    let(:bundle_user_plugin_default) { bundle_user_home_default.join("plugin") }
    let(:bundle_user_plugin_custom)  { xdg_data_home.join("bundle").join("plugin") }

    describe "#user_bundle_path" do
      before do
        allow(Bundler.rubygems).to receive(:user_home).and_return(home_path)
      end

      it "should use the default home path" do
        expect(Bundler.user_bundle_path).to           eq(bundle_user_home_default)
        expect(Bundler.user_bundle_path("home")).to   eq(bundle_user_home_default)
        expect(Bundler.user_bundle_path("cache")).to  eq(bundle_user_cache_default)
        expect(Bundler.user_cache).to                 eq(bundle_user_cache_default)
        expect(Bundler.user_bundle_path("config")).to eq(bundle_user_config_default)
        expect(Bundler.user_bundle_path("plugin")).to eq(bundle_user_plugin_default)
      end

      it "should use custom home path as root for other paths" do
        ENV["BUNDLE_USER_HOME"] = bundle_user_home_custom.to_s
        allow(Bundler.rubygems).to receive(:user_home).and_raise
        expect(Bundler.user_bundle_path).to           eq(bundle_user_home_custom)
        expect(Bundler.user_bundle_path("home")).to   eq(bundle_user_home_custom)
        expect(Bundler.user_bundle_path("cache")).to  eq(bundle_user_home_custom.join("cache"))
        expect(Bundler.user_cache).to                 eq(bundle_user_home_custom.join("cache"))
        expect(Bundler.user_bundle_path("config")).to eq(bundle_user_home_custom.join("config"))
        expect(Bundler.user_bundle_path("plugin")).to eq(bundle_user_home_custom.join("plugin"))
      end

      it "should use all custom paths, except home" do
        ENV.delete("BUNDLE_USER_HOME")
        ENV["BUNDLE_USER_CACHE"]  = bundle_user_cache_custom.to_s
        ENV["BUNDLE_USER_CONFIG"] = bundle_user_config_custom.to_s
        ENV["BUNDLE_USER_PLUGIN"] = bundle_user_plugin_custom.to_s
        expect(Bundler.user_bundle_path).to           eq(bundle_user_home_default)
        expect(Bundler.user_bundle_path("home")).to   eq(bundle_user_home_default)
        expect(Bundler.user_bundle_path("cache")).to  eq(bundle_user_cache_custom)
        expect(Bundler.user_cache).to                 eq(bundle_user_cache_custom)
        expect(Bundler.user_bundle_path("config")).to eq(bundle_user_config_custom)
        expect(Bundler.user_bundle_path("plugin")).to eq(bundle_user_plugin_custom)
      end
    end
  end
end
