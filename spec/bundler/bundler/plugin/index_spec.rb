# frozen_string_literal: true
require "spec_helper"

RSpec.describe Bundler::Plugin::Index do
  Index = Bundler::Plugin::Index

  before do
    gemfile ""
    path = lib_path(plugin_name)
    index.register_plugin("new-plugin", path.to_s, [path.join("lib").to_s], commands, sources, hooks)
  end

  let(:plugin_name) { "new-plugin" }
  let(:commands) { [] }
  let(:sources) { [] }
  let(:hooks) { [] }

  subject(:index) { Index.new }

  describe "#register plugin" do
    it "is available for retrieval" do
      expect(index.plugin_path(plugin_name)).to eq(lib_path(plugin_name))
    end

    it "load_paths is available for retrival" do
      expect(index.load_paths(plugin_name)).to eq([lib_path(plugin_name).join("lib").to_s])
    end

    it "is persistent" do
      new_index = Index.new
      expect(new_index.plugin_path(plugin_name)).to eq(lib_path(plugin_name))
    end

    it "load_paths are persistent" do
      new_index = Index.new
      expect(new_index.load_paths(plugin_name)).to eq([lib_path(plugin_name).join("lib").to_s])
    end
  end

  describe "commands" do
    let(:commands) { ["newco"] }

    it "returns the plugins name on query" do
      expect(index.command_plugin("newco")).to eq(plugin_name)
    end

    it "raises error on conflict" do
      expect do
        index.register_plugin("aplugin", lib_path("aplugin").to_s, lib_path("aplugin").join("lib").to_s, ["newco"], [], [])
      end.to raise_error(Index::CommandConflict)
    end

    it "is persistent" do
      new_index = Index.new
      expect(new_index.command_plugin("newco")).to eq(plugin_name)
    end
  end

  describe "source" do
    let(:sources) { ["new_source"] }

    it "returns the plugins name on query" do
      expect(index.source_plugin("new_source")).to eq(plugin_name)
    end

    it "raises error on conflict" do
      expect do
        index.register_plugin("aplugin", lib_path("aplugin").to_s, lib_path("aplugin").join("lib").to_s, [], ["new_source"], [])
      end.to raise_error(Index::SourceConflict)
    end

    it "is persistent" do
      new_index = Index.new
      expect(new_index.source_plugin("new_source")).to eq(plugin_name)
    end
  end

  describe "hook" do
    let(:hooks) { ["after-bar"] }

    it "returns the plugins name on query" do
      expect(index.hook_plugins("after-bar")).to include(plugin_name)
    end

    it "is persistent" do
      new_index = Index.new
      expect(new_index.hook_plugins("after-bar")).to eq([plugin_name])
    end

    context "that are not registered", :focused do
      let(:file) { double("index-file") }

      before do
        index.hook_plugins("not-there")
        allow(File).to receive(:open).and_yield(file)
      end

      it "should not save it with next registered hook" do
        expect(file).to receive(:puts) do |content|
          expect(content).not_to include("not-there")
        end

        index.register_plugin("aplugin", lib_path("aplugin").to_s, lib_path("aplugin").join("lib").to_s, [], [], [])
      end
    end
  end

  describe "global index" do
    before do
      Dir.chdir(tmp) do
        Bundler::Plugin.reset!
        path = lib_path("gplugin")
        index.register_plugin("gplugin", path.to_s, [path.join("lib").to_s], [], ["glb_source"], [])
      end
    end

    it "skips sources" do
      new_index = Index.new
      expect(new_index.source_plugin("glb_source")).to be_falsy
    end
  end

  describe "after conflict" do
    let(:commands) { ["foo"] }
    let(:sources) { ["bar"] }
    let(:hooks) { ["hoook"] }

    shared_examples "it cleans up" do
      it "the path" do
        expect(index.installed?("cplugin")).to be_falsy
      end

      it "the command" do
        expect(index.command_plugin("xfoo")).to be_falsy
      end

      it "the source" do
        expect(index.source_plugin("xbar")).to be_falsy
      end

      it "the hook" do
        expect(index.hook_plugins("xhoook")).to be_empty
      end
    end

    context "on command conflict it cleans up" do
      before do
        expect do
          path = lib_path("cplugin")
          index.register_plugin("cplugin", path.to_s, [path.join("lib").to_s], ["foo"], ["xbar"], ["xhoook"])
        end.to raise_error(Index::CommandConflict)
      end

      include_examples "it cleans up"
    end

    context "on source conflict it cleans up" do
      before do
        expect do
          path = lib_path("cplugin")
          index.register_plugin("cplugin", path.to_s, [path.join("lib").to_s], ["xfoo"], ["bar"], ["xhoook"])
        end.to raise_error(Index::SourceConflict)
      end

      include_examples "it cleans up"
    end

    context "on command and source conflict it cleans up" do
      before do
        expect do
          path = lib_path("cplugin")
          index.register_plugin("cplugin", path.to_s, [path.join("lib").to_s], ["foo"], ["bar"], ["xhoook"])
        end.to raise_error(Index::CommandConflict)
      end

      include_examples "it cleans up"
    end
  end
end
