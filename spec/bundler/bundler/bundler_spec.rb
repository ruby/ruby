# encoding: utf-8
# frozen_string_literal: true
require "spec_helper"
require "bundler"

describe Bundler do
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
  end

  describe "#which" do
    let(:executable) { "executable" }
    let(:path) { %w(/a /b c ../d /e) }
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
        settings = { :disable_shared_gems => true }
        Bundler.send(:configure_gem_path, env, settings)
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
        allow(FileUtils).to receive(:remove_entry_secure).and_raise(ArgumentError)
        allow(File).to receive(:world_writable?).and_return(true)
        message = <<EOF
It is a security vulnerability to allow your home directory to be world-writable, and bundler can not continue.
You should probably consider fixing this issue by running `chmod o-w ~` on *nix.
Please refer to http://ruby-doc.org/stdlib-2.1.2/libdoc/fileutils/rdoc/FileUtils.html#method-c-remove_entry_secure for details.
EOF
        expect(bundler_ui).to receive(:warn).with(message)
        expect { Bundler.send(:rm_rf, bundled_app) }.to raise_error(Bundler::PathError)
      end
    end
  end
end
