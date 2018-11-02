# frozen_string_literal: true

RSpec.describe Bundler::Plugin::API::Source do
  let(:uri) { "uri://to/test" }
  let(:type) { "spec_type" }

  subject(:source) do
    klass = Class.new
    klass.send :include, Bundler::Plugin::API::Source
    klass.new("uri" => uri, "type" => type)
  end

  describe "attributes" do
    it "allows access to uri" do
      expect(source.uri).to eq("uri://to/test")
    end

    it "allows access to name" do
      expect(source.name).to eq("spec_type at uri://to/test")
    end
  end

  context "post_install" do
    let(:installer) { double(:installer) }

    before do
      allow(Bundler::Source::Path::Installer).to receive(:new) { installer }
    end

    it "calls Path::Installer's post_install" do
      expect(installer).to receive(:post_install).once

      source.post_install(double(:spec))
    end
  end

  context "install_path" do
    let(:uri) { "uri://to/a/repository-name" }
    let(:hash) { Digest(:SHA1).hexdigest(uri) }
    let(:install_path) { Pathname.new "/bundler/install/path" }

    before do
      allow(Bundler).to receive(:install_path) { install_path }
    end

    it "returns basename with uri_hash" do
      expected = Pathname.new "#{install_path}/repository-name-#{hash[0..11]}"
      expect(source.install_path).to eq(expected)
    end
  end

  context "to_lock" do
    it "returns the string with remote and type" do
      expected = strip_whitespace <<-L
        PLUGIN SOURCE
          remote: #{uri}
          type: #{type}
          specs:
      L

      expect(source.to_lock).to eq(expected)
    end

    context "with additional options to lock" do
      before do
        allow(source).to receive(:options_to_lock) { { "first" => "option" } }
      end

      it "includes them" do
        expected = strip_whitespace <<-L
          PLUGIN SOURCE
            remote: #{uri}
            type: #{type}
            first: option
            specs:
        L

        expect(source.to_lock).to eq(expected)
      end
    end
  end
end
