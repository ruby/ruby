# frozen_string_literal: true
require "spec_helper"

RSpec.describe Bundler::Plugin::DSL do
  DSL = Bundler::Plugin::DSL

  subject(:dsl) { Bundler::Plugin::DSL.new }

  before do
    allow(Bundler).to receive(:root) { Pathname.new "/" }
  end

  describe "it ignores only the methods defined in Bundler::Dsl" do
    it "doesn't raises error for Dsl methods" do
      expect { dsl.install_if }.not_to raise_error
    end

    it "raises error for other methods" do
      expect { dsl.no_method }.to raise_error(DSL::PluginGemfileError)
    end
  end

  describe "source block" do
    it "adds #source with :type to list and also inferred_plugins list" do
      expect(dsl).to receive(:plugin).with("bundler-source-news").once

      dsl.source("some_random_url", :type => "news") {}

      expect(dsl.inferred_plugins).to eq(["bundler-source-news"])
    end

    it "registers a source type plugin only once for multiple declataions" do
      expect(dsl).to receive(:plugin).with("bundler-source-news").and_call_original.once

      dsl.source("some_random_url", :type => "news") {}
      dsl.source("another_random_url", :type => "news") {}
    end
  end
end
