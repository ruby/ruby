# frozen_string_literal: true

require "bundler"
require "tmpdir"

RSpec.describe Bundler do
  describe "#load_marshal" do
    it "loads any data" do
      data = Marshal.dump(Bundler)
      expect(Bundler.load_marshal(data)).to eq(Bundler)
    end
  end

  describe "#safe_load_marshal" do
    it "fails on unexpected class" do
      data = Marshal.dump(Bundler)
      expect { Bundler.safe_load_marshal(data) }.to raise_error(Bundler::MarshalError)
    end

    it "loads simple structure" do
      simple_structure = { "name" => [:abc] }
      data = Marshal.dump(simple_structure)
      expect(Bundler.safe_load_marshal(data)).to eq(simple_structure)
    end
  end

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

    let(:path) do
      if Gem.win_platform?
        %w[C:/a C:/b C:/c C:/../d C:/e]
      else
        %w[/a /b c ../d /e]
      end
    end

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
      let(:expected) do
        if Gem.win_platform?
          "C:/e/executable"
        else
          "/e/executable"
        end
      end
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
        expect(Bundler).to receive(:use_system_gems?).and_return(false)
        Bundler.send(:configure_gem_path)
        expect(ENV["GEM_PATH"]).to eq ""
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
It is a security vulnerability to allow your home directory to be world-writable, and bundler cannot continue.
You should probably consider fixing this issue by running `chmod o-w ~` on *nix.
Please refer to https://ruby-doc.org/stdlib-3.1.2/libdoc/fileutils/rdoc/FileUtils.html#method-c-remove_entry_secure for details.
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

      allow(Bundler).to receive(:root).and_return(bundled_app)

      Bundler.mkdir_p(bundled_app.join("foo", "bar"))
      expect(bundled_app.join("foo", "bar")).to exist
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
          expect(Bundler.ui).to receive(:warn).with("`/home/oggy` is not a directory.\n")
          expect(Bundler.ui).to receive(:warn).with("Bundler will use `/tmp/trulyrandom' as your home directory temporarily.\n")
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
          expect(Bundler.ui).to receive(:warn).with("`/home/oggy` is not writable.\n")
          expect(Bundler.ui).to receive(:warn).with("Bundler will use `/tmp/trulyrandom' as your home directory temporarily.\n")
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
        expect(Bundler.ui).to receive(:warn).with("Your home directory is not set.\n")
        expect(Bundler.ui).to receive(:warn).with("Bundler will use `/tmp/trulyrandom' as your home directory temporarily.\n")
        expect(Bundler.user_home).to eq(Pathname("/tmp/trulyrandom"))
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
