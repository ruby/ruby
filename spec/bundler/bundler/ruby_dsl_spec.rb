# frozen_string_literal: true

require "bundler/ruby_dsl"

RSpec.describe Bundler::RubyDsl do
  class MockDSL
    include Bundler::RubyDsl

    attr_reader :ruby_version
  end

  let(:dsl) { MockDSL.new }
  let(:ruby_version) { "2.0.0" }
  let(:ruby_version_arg) { ruby_version }
  let(:version) { "2.0.0" }
  let(:engine) { "jruby" }
  let(:engine_version) { "9000" }
  let(:patchlevel) { "100" }
  let(:options) do
    { :patchlevel => patchlevel,
      :engine => engine,
      :engine_version => engine_version }
  end

  let(:invoke) do
    proc do
      args = []
      args << Array(ruby_version_arg) if ruby_version_arg
      args << options

      dsl.ruby(*args)
    end
  end

  subject do
    invoke.call
    dsl.ruby_version
  end

  describe "#ruby_version" do
    shared_examples_for "it stores the ruby version" do
      it "stores the version" do
        expect(subject.versions).to eq(Array(ruby_version))
        expect(subject.gem_version.version).to eq(version)
      end

      it "stores the engine details" do
        expect(subject.engine).to eq(engine)
        expect(subject.engine_versions).to eq(Array(engine_version))
      end

      it "stores the patchlevel" do
        expect(subject.patchlevel).to eq(patchlevel)
      end
    end

    context "with a plain version" do
      it_behaves_like "it stores the ruby version"
    end

    context "with a single requirement" do
      let(:ruby_version) { ">= 2.0.0" }
      it_behaves_like "it stores the ruby version"
    end

    context "with two requirements in the same string" do
      let(:ruby_version) { ">= 2.0.0, < 3.0" }
      it "raises an error" do
        expect { subject }.to raise_error(ArgumentError)
      end
    end

    context "with two requirements" do
      let(:ruby_version) { ["~> 2.0.0", "> 2.0.1"] }
      it_behaves_like "it stores the ruby version"
    end

    context "with multiple engine versions" do
      let(:engine_version) { ["> 200", "< 300"] }
      it_behaves_like "it stores the ruby version"
    end

    context "with no options hash" do
      let(:invoke) { proc { dsl.ruby(ruby_version) } }

      let(:patchlevel) { nil }
      let(:engine) { "ruby" }
      let(:engine_version) { version }

      it_behaves_like "it stores the ruby version"

      context "and with multiple requirements" do
        let(:ruby_version) { ["~> 2.0.0", "> 2.0.1"] }
        let(:engine_version) { ruby_version }
        it_behaves_like "it stores the ruby version"
      end
    end

    context "with a file option" do
      let(:options) { { :file => "foo" } }
      let(:version) { "3.2.2" }
      let(:ruby_version) { "3.2.2" }
      let(:ruby_version_arg) { nil }
      let(:engine_version) { version }
      let(:patchlevel) { nil }
      let(:engine) { "ruby" }
      let(:project_root) { Pathname.new("/path/to/project") }

      before do
        allow(Bundler).to receive(:read_file).with(project_root.join("foo")).and_return("#{version}\n")
        allow(Bundler).to receive(:root).and_return(Pathname.new("/path/to/project"))
      end

      it_behaves_like "it stores the ruby version"

      context "and a version" do
        let(:ruby_version_arg) { "2.0.0" }

        it "raises an error" do
          expect { subject }.to raise_error(Bundler::GemfileError, "Cannot specify version when using the file option")
        end
      end
    end

    context "with a (.tool-versions) file option" do
      let(:options) { { :file => "foo" } }
      let(:version) { "3.2.2" }
      let(:ruby_version) { "3.2.2" }
      let(:ruby_version_arg) { nil }
      let(:engine_version) { version }
      let(:patchlevel) { nil }
      let(:engine) { "ruby" }
      let(:project_root) { Pathname.new("/path/to/project") }

      before do
        allow(Bundler).to receive(:read_file).with(project_root.join("foo")).and_return("nodejs 18.16.0\nruby #{version} # This is a comment\npnpm 8.6.12\n")
        allow(Bundler).to receive(:root).and_return(Pathname.new("/path/to/project"))
      end

      it_behaves_like "it stores the ruby version"

      context "and a version" do
        let(:ruby_version_arg) { "2.0.0" }

        it "raises an error" do
          expect { subject }.to raise_error(Bundler::GemfileError, "Cannot specify version when using the file option")
        end
      end
    end
  end
end
