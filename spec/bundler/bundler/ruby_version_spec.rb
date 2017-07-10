# frozen_string_literal: true
require "spec_helper"
require "bundler/ruby_version"

describe "Bundler::RubyVersion and its subclasses" do
  let(:version)              { "2.0.0" }
  let(:patchlevel)           { "645" }
  let(:engine)               { "jruby" }
  let(:engine_version)       { "2.0.1" }

  describe Bundler::RubyVersion do
    subject { Bundler::RubyVersion.new(version, patchlevel, engine, engine_version) }

    let(:ruby_version)         { subject }
    let(:other_version)        { version }
    let(:other_patchlevel)     { patchlevel }
    let(:other_engine)         { engine }
    let(:other_engine_version) { engine_version }
    let(:other_ruby_version)   { Bundler::RubyVersion.new(other_version, other_patchlevel, other_engine, other_engine_version) }

    describe "#initialize" do
      context "no engine is passed" do
        let(:engine) { nil }

        it "should set ruby as the engine" do
          expect(subject.engine).to eq("ruby")
        end
      end

      context "no engine_version is passed" do
        let(:engine_version) { nil }

        it "should set engine version as the passed version" do
          expect(subject.engine_versions).to eq(["2.0.0"])
        end
      end

      context "with engine in symbol" do
        let(:engine) { :jruby }

        it "should coerce engine to string" do
          expect(subject.engine).to eq("jruby")
        end
      end

      context "is called with multiple requirements" do
        let(:version) { ["<= 2.0.0", "> 1.9.3"] }
        let(:engine_version) { nil }

        it "sets the versions" do
          expect(subject.versions).to eq(version)
        end

        it "sets the engine versions" do
          expect(subject.engine_versions).to eq(version)
        end
      end

      context "is called with multiple engine requirements" do
        let(:engine_version) { [">= 2.0", "< 2.3"] }

        it "sets the engine versions" do
          expect(subject.engine_versions).to eq(engine_version)
        end
      end
    end

    describe ".from_string" do
      shared_examples_for "returning" do
        it "returns the original RubyVersion" do
          expect(described_class.from_string(subject.to_s)).to eq(subject)
        end
      end

      include_examples "returning"

      context "no patchlevel" do
        let(:patchlevel) { nil }

        include_examples "returning"
      end

      context "engine is ruby" do
        let(:engine) { "ruby" }
        let(:engine_version) { version }

        include_examples "returning"
      end

      context "with multiple requirements" do
        let(:engine_version) { ["> 9", "< 11"] }
        let(:version) { ["> 8", "< 10"] }
        let(:patchlevel) { nil }

        it "returns nil" do
          expect(described_class.from_string(subject.to_s)).to be_nil
        end
      end
    end

    describe "#to_s" do
      it "should return info string with the ruby version, patchlevel, engine, and engine version" do
        expect(subject.to_s).to eq("ruby 2.0.0p645 (jruby 2.0.1)")
      end

      context "no patchlevel" do
        let(:patchlevel) { nil }

        it "should return info string with the version, engine, and engine version" do
          expect(subject.to_s).to eq("ruby 2.0.0 (jruby 2.0.1)")
        end
      end

      context "engine is ruby" do
        let(:engine) { "ruby" }

        it "should return info string with the ruby version and patchlevel" do
          expect(subject.to_s).to eq("ruby 2.0.0p645")
        end
      end

      context "with multiple requirements" do
        let(:engine_version) { ["> 9", "< 11"] }
        let(:version) { ["> 8", "< 10"] }
        let(:patchlevel) { nil }

        it "should return info string with all requirements" do
          expect(subject.to_s).to eq("ruby > 8, < 10 (jruby > 9, < 11)")
        end
      end
    end

    describe "#==" do
      shared_examples_for "two ruby versions are not equal" do
        it "should return false" do
          expect(subject).to_not eq(other_ruby_version)
        end
      end

      context "the versions, pathlevels, engines, and engine_versions match" do
        it "should return true" do
          expect(subject).to eq(other_ruby_version)
        end
      end

      context "the versions do not match" do
        let(:other_version) { "1.21.6" }

        it_behaves_like "two ruby versions are not equal"
      end

      context "the patchlevels do not match" do
        let(:other_patchlevel) { "21" }

        it_behaves_like "two ruby versions are not equal"
      end

      context "the engines do not match" do
        let(:other_engine) { "ruby" }

        it_behaves_like "two ruby versions are not equal"
      end

      context "the engine versions do not match" do
        let(:other_engine_version) { "1.11.2" }

        it_behaves_like "two ruby versions are not equal"
      end
    end

    describe "#host" do
      before do
        allow(RbConfig::CONFIG).to receive(:[]).with("host_cpu").and_return("x86_64")
        allow(RbConfig::CONFIG).to receive(:[]).with("host_vendor").and_return("apple")
        allow(RbConfig::CONFIG).to receive(:[]).with("host_os").and_return("darwin14.5.0")
      end

      it "should return an info string with the host cpu, vendor, and os" do
        expect(subject.host).to eq("x86_64-apple-darwin14.5.0")
      end

      it "memoizes the info string with the host cpu, vendor, and os" do
        expect(RbConfig::CONFIG).to receive(:[]).with("host_cpu").once.and_call_original
        expect(RbConfig::CONFIG).to receive(:[]).with("host_vendor").once.and_call_original
        expect(RbConfig::CONFIG).to receive(:[]).with("host_os").once.and_call_original
        2.times { ruby_version.host }
      end
    end

    describe "#gem_version" do
      let(:gem_version) { "2.0.0" }
      let(:gem_version_obj) { Gem::Version.new(gem_version) }

      shared_examples_for "it parses the version from the requirement string" do |version|
        let(:version) { version }
        it "should return the underlying version" do
          expect(ruby_version.gem_version).to eq(gem_version_obj)
          expect(ruby_version.gem_version.version).to eq(gem_version)
        end
      end

      it_behaves_like "it parses the version from the requirement string", "2.0.0"
      it_behaves_like "it parses the version from the requirement string", ">= 2.0.0"
      it_behaves_like "it parses the version from the requirement string", "~> 2.0.0"
      it_behaves_like "it parses the version from the requirement string", "< 2.0.0"
      it_behaves_like "it parses the version from the requirement string", "= 2.0.0"
      it_behaves_like "it parses the version from the requirement string", ["> 2.0.0", "< 2.4.5"]
    end

    describe "#diff" do
      let(:engine) { "ruby" }

      shared_examples_for "there is a difference in the engines" do
        it "should return a tuple with :engine and the two different engines" do
          expect(ruby_version.diff(other_ruby_version)).to eq([:engine, engine, other_engine])
        end
      end

      shared_examples_for "there is a difference in the versions" do
        it "should return a tuple with :version and the two different versions" do
          expect(ruby_version.diff(other_ruby_version)).to eq([:version, Array(version).join(", "), Array(other_version).join(", ")])
        end
      end

      shared_examples_for "there is a difference in the engine versions" do
        it "should return a tuple with :engine_version and the two different engine versions" do
          expect(ruby_version.diff(other_ruby_version)).to eq([:engine_version, Array(engine_version).join(", "), Array(other_engine_version).join(", ")])
        end
      end

      shared_examples_for "there is a difference in the patchlevels" do
        it "should return a tuple with :patchlevel and the two different patchlevels" do
          expect(ruby_version.diff(other_ruby_version)).to eq([:patchlevel, patchlevel, other_patchlevel])
        end
      end

      shared_examples_for "there are no differences" do
        it "should return nil" do
          expect(ruby_version.diff(other_ruby_version)).to be_nil
        end
      end

      context "all things match exactly" do
        it_behaves_like "there are no differences"
      end

      context "detects engine discrepancies first" do
        let(:other_version)        { "2.0.1" }
        let(:other_patchlevel)     { "643" }
        let(:other_engine)         { "rbx" }
        let(:other_engine_version) { "2.0.0" }

        it_behaves_like "there is a difference in the engines"
      end

      context "detects version discrepancies second" do
        let(:other_version)        { "2.0.1" }
        let(:other_patchlevel)     { "643" }
        let(:other_engine_version) { "2.0.0" }

        it_behaves_like "there is a difference in the versions"
      end

      context "detects version discrepancies with multiple requirements second" do
        let(:other_version)        { "2.0.1" }
        let(:other_patchlevel)     { "643" }
        let(:other_engine_version) { "2.0.0" }

        let(:version) { ["> 2.0.0", "< 1.0.0"] }

        it_behaves_like "there is a difference in the versions"
      end

      context "detects engine version discrepancies third" do
        let(:other_patchlevel)     { "643" }
        let(:other_engine_version) { "2.0.0" }

        it_behaves_like "there is a difference in the engine versions"
      end

      context "detects engine version discrepancies with multiple requirements third" do
        let(:other_patchlevel)     { "643" }
        let(:other_engine_version) { "2.0.0" }

        let(:engine_version) { ["> 2.0.0", "< 1.0.0"] }

        it_behaves_like "there is a difference in the engine versions"
      end

      context "detects patchlevel discrepancies last" do
        let(:other_patchlevel) { "643" }

        it_behaves_like "there is a difference in the patchlevels"
      end

      context "successfully matches gem requirements" do
        let(:version)              { ">= 2.0.0" }
        let(:patchlevel)           { "< 643" }
        let(:engine)               { "ruby" }
        let(:engine_version)       { "~> 2.0.1" }
        let(:other_version)        { "2.0.0" }
        let(:other_patchlevel)     { "642" }
        let(:other_engine)         { "ruby" }
        let(:other_engine_version) { "2.0.5" }

        it_behaves_like "there are no differences"
      end

      context "successfully matches multiple gem requirements" do
        let(:version)              { [">= 2.0.0", "< 2.4.5"] }
        let(:patchlevel)           { "< 643" }
        let(:engine)               { "ruby" }
        let(:engine_version)       { ["~> 2.0.1", "< 2.4.5"] }
        let(:other_version)        { "2.0.0" }
        let(:other_patchlevel)     { "642" }
        let(:other_engine)         { "ruby" }
        let(:other_engine_version) { "2.0.5" }

        it_behaves_like "there are no differences"
      end

      context "successfully detects bad gem requirements with versions with multiple requirements" do
        let(:version)              { ["~> 2.0.0", "< 2.0.5"] }
        let(:patchlevel)           { "< 643" }
        let(:engine)               { "ruby" }
        let(:engine_version)       { "~> 2.0.1" }
        let(:other_version)        { "2.0.5" }
        let(:other_patchlevel)     { "642" }
        let(:other_engine)         { "ruby" }
        let(:other_engine_version) { "2.0.5" }

        it_behaves_like "there is a difference in the versions"
      end

      context "successfully detects bad gem requirements with versions" do
        let(:version)              { "~> 2.0.0" }
        let(:patchlevel)           { "< 643" }
        let(:engine)               { "ruby" }
        let(:engine_version)       { "~> 2.0.1" }
        let(:other_version)        { "2.1.0" }
        let(:other_patchlevel)     { "642" }
        let(:other_engine)         { "ruby" }
        let(:other_engine_version) { "2.0.5" }

        it_behaves_like "there is a difference in the versions"
      end

      context "successfully detects bad gem requirements with patchlevels" do
        let(:version)              { ">= 2.0.0" }
        let(:patchlevel)           { "< 643" }
        let(:engine)               { "ruby" }
        let(:engine_version)       { "~> 2.0.1" }
        let(:other_version)        { "2.0.0" }
        let(:other_patchlevel)     { "645" }
        let(:other_engine)         { "ruby" }
        let(:other_engine_version) { "2.0.5" }

        it_behaves_like "there is a difference in the patchlevels"
      end

      context "successfully detects bad gem requirements with engine versions" do
        let(:version)              { ">= 2.0.0" }
        let(:patchlevel)           { "< 643" }
        let(:engine)               { "ruby" }
        let(:engine_version)       { "~> 2.0.1" }
        let(:other_version)        { "2.0.0" }
        let(:other_patchlevel)     { "642" }
        let(:other_engine)         { "ruby" }
        let(:other_engine_version) { "2.1.0" }

        it_behaves_like "there is a difference in the engine versions"
      end

      context "with a patchlevel of -1" do
        let(:version)              { ">= 2.0.0" }
        let(:patchlevel)           { "-1" }
        let(:engine)               { "ruby" }
        let(:engine_version)       { "~> 2.0.1" }
        let(:other_version)        { version }
        let(:other_engine)         { engine }
        let(:other_engine_version) { engine_version }

        context "and comparing with another patchlevel of -1" do
          let(:other_patchlevel) { patchlevel }

          it_behaves_like "there are no differences"
        end

        context "and comparing with a patchlevel that is not -1" do
          let(:other_patchlevel)     { "642" }

          it_behaves_like "there is a difference in the patchlevels"
        end
      end
    end

    describe "#system" do
      subject { Bundler::RubyVersion.system }

      let(:bundler_system_ruby_version) { subject }

      before do
        Bundler::RubyVersion.instance_variable_set("@ruby_version", nil)
      end

      it "should return an instance of Bundler::RubyVersion" do
        expect(subject).to be_kind_of(Bundler::RubyVersion)
      end

      it "memoizes the instance of Bundler::RubyVersion" do
        expect(Bundler::RubyVersion).to receive(:new).once.and_call_original
        2.times { subject }
      end

      describe "#version" do
        it "should return a copy of the value of RUBY_VERSION" do
          expect(subject.versions).to eq([RUBY_VERSION])
          expect(subject.versions.first).to_not be(RUBY_VERSION)
        end
      end

      describe "#engine" do
        context "RUBY_ENGINE is defined" do
          before { stub_const("RUBY_ENGINE", "jruby") }
          before { stub_const("JRUBY_VERSION", "2.1.1") }

          it "should return a copy of the value of RUBY_ENGINE" do
            expect(subject.engine).to eq("jruby")
            expect(subject.engine).to_not be(RUBY_ENGINE)
          end
        end

        context "RUBY_ENGINE is not defined" do
          before { stub_const("RUBY_ENGINE", nil) }

          it "should return the string 'ruby'" do
            expect(subject.engine).to eq("ruby")
          end
        end
      end

      describe "#engine_version" do
        context "engine is ruby" do
          before do
            stub_const("RUBY_VERSION", "2.2.4")
            allow(Bundler).to receive(:ruby_engine).and_return("ruby")
          end

          it "should return a copy of the value of RUBY_VERSION" do
            expect(bundler_system_ruby_version.engine_versions).to eq(["2.2.4"])
            expect(bundler_system_ruby_version.engine_versions.first).to_not be(RUBY_VERSION)
          end
        end

        context "engine is rbx" do
          before do
            stub_const("RUBY_ENGINE", "rbx")
            stub_const("Rubinius::VERSION", "2.0.0")
          end

          it "should return a copy of the value of Rubinius::VERSION" do
            expect(bundler_system_ruby_version.engine_versions).to eq(["2.0.0"])
            expect(bundler_system_ruby_version.engine_versions.first).to_not be(Rubinius::VERSION)
          end
        end

        context "engine is jruby" do
          before do
            stub_const("RUBY_ENGINE", "jruby")
            stub_const("JRUBY_VERSION", "2.1.1")
          end

          it "should return a copy of the value of JRUBY_VERSION" do
            expect(subject.engine_versions).to eq(["2.1.1"])
            expect(bundler_system_ruby_version.engine_versions.first).to_not be(JRUBY_VERSION)
          end
        end

        context "engine is some other ruby engine" do
          before do
            stub_const("RUBY_ENGINE", "not_supported_ruby_engine")
            allow(Bundler).to receive(:ruby_engine).and_return("not_supported_ruby_engine")
          end

          it "should raise a BundlerError with a 'not recognized' message" do
            expect { bundler_system_ruby_version.engine_versions }.to raise_error(Bundler::BundlerError, "RUBY_ENGINE value not_supported_ruby_engine is not recognized")
          end
        end
      end

      describe "#patchlevel" do
        it "should return a string with the value of RUBY_PATCHLEVEL" do
          expect(subject.patchlevel).to eq(RUBY_PATCHLEVEL.to_s)
        end
      end
    end

    describe "#to_gem_version_with_patchlevel" do
      shared_examples_for "the patchlevel is omitted" do
        it "does not include a patch level" do
          expect(subject.to_gem_version_with_patchlevel.to_s).to eq(version)
        end
      end

      context "with nil patch number" do
        let(:patchlevel) { nil }

        it_behaves_like "the patchlevel is omitted"
      end

      context "with negative patch number" do
        let(:patchlevel) { -1 }

        it_behaves_like "the patchlevel is omitted"
      end

      context "with a valid patch number" do
        it "uses the specified patchlevel as patchlevel" do
          expect(subject.to_gem_version_with_patchlevel.to_s).to eq("#{version}.#{patchlevel}")
        end
      end
    end
  end
end
