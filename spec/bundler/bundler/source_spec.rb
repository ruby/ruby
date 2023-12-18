# frozen_string_literal: true

RSpec.describe Bundler::Source do
  class ExampleSource < Bundler::Source
  end

  subject { ExampleSource.new }

  describe "#unmet_deps" do
    let(:specs) { double(:specs) }
    let(:unmet_dependency_names) { double(:unmet_dependency_names) }

    before do
      allow(subject).to receive(:specs).and_return(specs)
      allow(specs).to receive(:unmet_dependency_names).and_return(unmet_dependency_names)
    end

    it "should return the names of unmet dependencies" do
      expect(subject.unmet_deps).to eq(unmet_dependency_names)
    end
  end

  describe "#version_message" do
    let(:spec) { double(:spec, name: "nokogiri", version: ">= 1.6", platform: rb) }

    shared_examples_for "the lockfile specs are not relevant" do
      it "should return a string with the spec name and version" do
        expect(subject.version_message(spec)).to eq("nokogiri >= 1.6")
      end
    end

    context "when there are locked gems" do
      context "that contain the relevant gem spec" do
        context "without a version" do
          let(:locked_gem) { double(:locked_gem, name: "nokogiri", version: nil) }

          it_behaves_like "the lockfile specs are not relevant"
        end

        context "with the same version" do
          let(:locked_gem) { double(:locked_gem, name: "nokogiri", version: ">= 1.6") }

          it_behaves_like "the lockfile specs are not relevant"
        end

        context "with a different version" do
          let(:locked_gem) { double(:locked_gem, name: "nokogiri", version: "< 1.5") }

          context "with color", :no_color_tty do
            before do
              allow($stdout).to receive(:tty?).and_return(true)
            end

            it "should return a string with the spec name and version and locked spec version" do
              expect(subject.version_message(spec, locked_gem)).to eq("nokogiri >= 1.6\e[32m (was < 1.5)\e[0m")
            end
          end

          context "without color" do
            around do |example|
              with_ui(Bundler::UI::Shell.new("no-color" => true)) do
                example.run
              end
            end

            it "should return a string with the spec name and version and locked spec version" do
              expect(subject.version_message(spec, locked_gem)).to eq("nokogiri >= 1.6 (was < 1.5)")
            end
          end
        end

        context "with a more recent version" do
          let(:spec) { double(:spec, name: "nokogiri", version: "1.6.1", platform: rb) }
          let(:locked_gem) { double(:locked_gem, name: "nokogiri", version: "1.7.0") }

          context "with color", :no_color_tty do
            before do
              allow($stdout).to receive(:tty?).and_return(true)
            end

            it "should return a string with the locked spec version in yellow" do
              expect(subject.version_message(spec, locked_gem)).to eq("nokogiri 1.6.1\e[33m (was 1.7.0)\e[0m")
            end
          end

          context "without color" do
            around do |example|
              with_ui(Bundler::UI::Shell.new("no-color" => true)) do
                example.run
              end
            end

            it "should return a string with the locked spec version in yellow" do
              expect(subject.version_message(spec, locked_gem)).to eq("nokogiri 1.6.1 (was 1.7.0)")
            end
          end
        end

        context "with an older version" do
          let(:spec) { double(:spec, name: "nokogiri", version: "1.7.1", platform: rb) }
          let(:locked_gem) { double(:locked_gem, name: "nokogiri", version: "1.7.0") }

          context "with color", :no_color_tty do
            before do
              allow($stdout).to receive(:tty?).and_return(true)
            end

            it "should return a string with the locked spec version in green" do
              expect(subject.version_message(spec, locked_gem)).to eq("nokogiri 1.7.1\e[32m (was 1.7.0)\e[0m")
            end
          end

          context "without color" do
            around do |example|
              with_ui(Bundler::UI::Shell.new("no-color" => true)) do
                example.run
              end
            end

            it "should return a string with the locked spec version in yellow" do
              expect(subject.version_message(spec, locked_gem)).to eq("nokogiri 1.7.1 (was 1.7.0)")
            end
          end
        end
      end
    end
  end

  describe "#can_lock?" do
    context "when the passed spec's source is equivalent" do
      let(:spec) { double(:spec, source: subject) }

      it "should return true" do
        expect(subject.can_lock?(spec)).to be_truthy
      end
    end

    context "when the passed spec's source is not equivalent" do
      let(:spec) { double(:spec, source: double(:other_source)) }

      it "should return false" do
        expect(subject.can_lock?(spec)).to be_falsey
      end
    end
  end

  describe "#include?" do
    context "when the passed source is equivalent" do
      let(:source) { subject }

      it "should return true" do
        expect(subject).to include(source)
      end
    end

    context "when the passed source is not equivalent" do
      let(:source) { double(:source) }

      it "should return false" do
        expect(subject).to_not include(source)
      end
    end
  end

  private

  def with_ui(ui)
    old_ui = Bundler.ui
    Bundler.ui = ui
    yield
  ensure
    Bundler.ui = old_ui
  end
end
