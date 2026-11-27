# frozen_string_literal: true

RSpec.describe Bundler::Plugin::UnloadedSource do
  let(:uri) { "uri://to/test" }

  def source(type)
    described_class.new("uri" => uri, "type" => type)
  end

  describe "equality" do
    it "treats sources with the same uri and type as equal" do
      a = source("type_a")
      b = source("type_a")

      expect(a).to eq(b)
      expect(a).to eql(b)
      expect(a.hash).to eq(b.hash)
    end

    it "treats sources with the same uri but different types as not equal" do
      a = source("type_a")
      b = source("type_b")

      expect(a).not_to eq(b)
      expect(a).not_to eql(b)
      expect(a.hash).not_to eq(b.hash)
    end

    it "is not equal to a real plugin source with the same uri and type" do
      klass = Class.new
      klass.send :include, Bundler::Plugin::API::Source

      expect(source("type_a")).not_to eq(klass.new("uri" => uri, "type" => "type_a"))
    end
  end
end
