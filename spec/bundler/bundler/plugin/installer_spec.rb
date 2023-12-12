# frozen_string_literal: true

RSpec.describe Bundler::Plugin::Installer do
  subject(:installer) { Bundler::Plugin::Installer.new }

  describe "cli install" do
    it "uses Gem.sources when non of the source is provided" do
      sources = double(:sources)
      Bundler.settings # initialize it before we have to touch rubygems.ext_lock
      allow(Gem).to receive(:sources) { sources }

      allow(installer).to receive(:install_rubygems).
        with("new-plugin", [">= 0"], sources).once

      installer.install("new-plugin", {})
    end

    describe "with mocked installers" do
      let(:spec) { double(:spec) }
      it "returns the installed spec after installing git plugins" do
        allow(installer).to receive(:install_git).
          and_return("new-plugin" => spec)

        expect(installer.install(["new-plugin"], git: "https://some.ran/dom")).
          to eq("new-plugin" => spec)
      end

      it "returns the installed spec after installing local git plugins" do
        allow(installer).to receive(:install_local_git).
          and_return("new-plugin" => spec)

        expect(installer.install(["new-plugin"], local_git: "/phony/path/repo")).
          to eq("new-plugin" => spec)
      end

      it "returns the installed spec after installing rubygems plugins" do
        allow(installer).to receive(:install_rubygems).
          and_return("new-plugin" => spec)

        expect(installer.install(["new-plugin"], source: "https://some.ran/dom")).
          to eq("new-plugin" => spec)
      end
    end

    describe "with actual installers" do
      before do
        build_repo2 do
          build_plugin "re-plugin"
          build_plugin "ma-plugin"
        end
      end

      context "git plugins" do
        before do
          build_git "ga-plugin", path: lib_path("ga-plugin") do |s|
            s.write "plugins.rb"
          end
        end

        let(:result) do
          installer.install(["ga-plugin"], git: file_uri_for(lib_path("ga-plugin")))
        end

        it "returns the installed spec after installing" do
          spec = result["ga-plugin"]
          expect(spec.full_name).to eq "ga-plugin-1.0"
        end

        it "has expected full_gem_path" do
          rev = revision_for(lib_path("ga-plugin"))
          expect(result["ga-plugin"].full_gem_path).
            to eq(Bundler::Plugin.root.join("bundler", "gems", "ga-plugin-#{rev[0..11]}").to_s)
        end
      end

      context "local git plugins" do
        before do
          build_git "ga-plugin", path: lib_path("ga-plugin") do |s|
            s.write "plugins.rb"
          end
        end

        let(:result) do
          installer.install(["ga-plugin"], local_git: lib_path("ga-plugin").to_s)
        end

        it "returns the installed spec after installing" do
          spec = result["ga-plugin"]
          expect(spec.full_name).to eq "ga-plugin-1.0"
        end

        it "has expected full_gem_path" do
          rev = revision_for(lib_path("ga-plugin"))
          expect(result["ga-plugin"].full_gem_path).
            to eq(Bundler::Plugin.root.join("bundler", "gems", "ga-plugin-#{rev[0..11]}").to_s)
        end
      end

      context "rubygems plugins" do
        let(:result) do
          installer.install(["re-plugin"], source: file_uri_for(gem_repo2))
        end

        it "returns the installed spec after installing " do
          expect(result["re-plugin"]).to be_kind_of(Bundler::RemoteSpecification)
        end

        it "has expected full_gem_path" do
          expect(result["re-plugin"].full_gem_path).
            to eq(global_plugin_gem("re-plugin-1.0").to_s)
        end
      end

      context "multiple plugins" do
        let(:result) do
          installer.install(["re-plugin", "ma-plugin"], source: file_uri_for(gem_repo2))
        end

        it "returns the installed spec after installing " do
          expect(result["re-plugin"]).to be_kind_of(Bundler::RemoteSpecification)
          expect(result["ma-plugin"]).to be_kind_of(Bundler::RemoteSpecification)
        end

        it "has expected full_gem_path" do
          expect(result["re-plugin"].full_gem_path).to eq(global_plugin_gem("re-plugin-1.0").to_s)
          expect(result["ma-plugin"].full_gem_path).to eq(global_plugin_gem("ma-plugin-1.0").to_s)
        end
      end
    end
  end
end
