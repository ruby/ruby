# frozen_string_literal: true
require "spec_helper"

describe Bundler::EnvironmentPreserver do
  let(:preserver) { described_class.new(env, ["foo"]) }

  describe "#backup" do
    let(:env) { { "foo" => "my-foo", "bar" => "my-bar" } }
    subject { preserver.backup }

    it "should create backup entries" do
      expect(subject["BUNDLER_ORIG_foo"]).to eq("my-foo")
    end

    it "should keep the original entry" do
      expect(subject["foo"]).to eq("my-foo")
    end

    it "should not create backup entries for unspecified keys" do
      expect(subject.key?("BUNDLER_ORIG_bar")).to eq(false)
    end

    it "should not affect the original env" do
      subject
      expect(env.keys.sort).to eq(%w(bar foo))
    end

    context "when a key is empty" do
      let(:env) { { "foo" => "" } }

      it "should not create backup entries" do
        expect(subject.key?("BUNDLER_ORIG_foo")).to eq(false)
      end
    end

    context "when an original key is set" do
      let(:env) { { "foo" => "my-foo", "BUNDLER_ORIG_foo" => "orig-foo" } }

      it "should keep the original value in the BUNDLER_ORIG_ variable" do
        expect(subject["BUNDLER_ORIG_foo"]).to eq("orig-foo")
      end

      it "should keep the variable" do
        expect(subject["foo"]).to eq("my-foo")
      end
    end
  end

  describe "#restore" do
    subject { preserver.restore }

    context "when an original key is set" do
      let(:env) { { "foo" => "my-foo", "BUNDLER_ORIG_foo" => "orig-foo" } }

      it "should restore the original value" do
        expect(subject["foo"]).to eq("orig-foo")
      end

      it "should delete the backup value" do
        expect(subject.key?("BUNDLER_ORIG_foo")).to eq(false)
      end
    end

    context "when no original key is set" do
      let(:env) { { "foo" => "my-foo" } }

      it "should keep the current value" do
        expect(subject["foo"]).to eq("my-foo")
      end
    end

    context "when the original key is empty" do
      let(:env) { { "foo" => "my-foo", "BUNDLER_ORIG_foo" => "" } }

      it "should keep the current value" do
        expect(subject["foo"]).to eq("my-foo")
      end
    end
  end
end
