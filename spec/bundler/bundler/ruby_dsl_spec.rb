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
    { patchlevel: patchlevel,
      engine: engine,
      engine_version: engine_version }
  end
  let(:project_root) { Pathname.new("/path/to/project") }
  before { allow(Bundler).to receive(:root).and_return(project_root) }

  let(:invoke) do
    proc do
      args = []
      args << ruby_version_arg if ruby_version_arg
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

    context "with a preview version" do
      let(:ruby_version) { "3.3.0-preview2" }

      it "stores the version" do
        expect(subject.versions).to eq(Array("3.3.0.preview2"))
        expect(subject.gem_version.version).to eq("3.3.0.preview2")
      end
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
      let(:file) { ".ruby-version" }
      let(:options) do
        { file: file,
          patchlevel: patchlevel,
          engine: engine,
          engine_version: engine_version }
      end
      let(:ruby_version_arg) { nil }
      let(:file_content) { "#{version}\n" }

      before do
        allow(Bundler).to receive(:read_file).with(project_root.join(file)).and_return(file_content)
      end

      it_behaves_like "it stores the ruby version"

      context "with the ruby- prefix in the file" do
        let(:file_content) { "ruby-#{version}\n" }

        it_behaves_like "it stores the ruby version"
      end

      context "and a version" do
        let(:ruby_version_arg) { version }

        it "raises an error" do
          expect { subject }.to raise_error(Bundler::GemfileError, "Do not pass version argument when using :file option")
        end
      end

      context "with a @gemset" do
        let(:file_content) { "ruby-#{version}@gemset\n" }

        it "raises an error" do
          expect { subject }.to raise_error(Gem::Requirement::BadRequirementError, "Illformed requirement [\"#{version}@gemset\"]")
        end
      end

      context "with a .tool-versions file format" do
        let(:file) { ".tool-versions" }
        let(:ruby_version_arg) { nil }
        let(:file_content) do
          <<~TOOLS
            nodejs 18.16.0
            ruby #{version} # This is a comment
            pnpm 8.6.12
          TOOLS
        end

        it_behaves_like "it stores the ruby version"

        context "with extra spaces and a very cozy comment" do
          let(:file_content) do
            <<~TOOLS
              nodejs 18.16.0
              ruby   #{version}# This is a cozy comment
              pnpm   8.6.12
            TOOLS
          end

          it_behaves_like "it stores the ruby version"
        end
      end
    end
  end
end
