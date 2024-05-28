# frozen_string_literal: true

require "bundler/compact_index_client"
require "bundler/compact_index_client/parser"

TestCompactIndexClient = Struct.new(:names, :versions, :info_data) do
  # Requiring the checksum to match the input data helps ensure
  # that we are parsing the correct checksum from the versions file
  def info(name, checksum)
    info_data.dig(name, checksum)
  end

  def set_info_data(name, value)
    info_data[name] = value
  end
end

RSpec.describe Bundler::CompactIndexClient::Parser do
  subject(:parser) { described_class.new(compact_index) }

  let(:compact_index) { TestCompactIndexClient.new(names, versions, info_data) }
  let(:names) { "a\nb\nc\n" }
  let(:versions) { <<~VERSIONS }
    a 1.0.0,1.0.1,1.1.0 aaa111
    b 2.0.0,2.0.0-java bbb222
    c 3.0.0,3.0.3,3.3.3 ccc333
    c -3.0.3 ccc333yanked
  VERSIONS
  let(:info_data) do
    {
      "a" => { "aaa111" => a_info },
      "b" => { "bbb222" => b_info },
      "c" => { "ccc333yanked" => c_info },
    }
  end
  let(:a_info) { <<~INFO }
    1.0.0 |checksum:aaa1,ruby:>= 3.0.0,rubygems:>= 3.2.3
    1.0.1 |checksum:aaa2,ruby:>= 3.0.0,rubygems:>= 3.2.3
    1.1.0 |checksum:aaa3,ruby:>= 3.0.0,rubygems:>= 3.2.3
  INFO
  let(:b_info) { <<~INFO }
    2.0.0 a:~> 1.0&<= 3.0|checksum:bbb1
    2.0.0-java a:~> 1.0&<= 3.0|checksum:bbb2
  INFO
  let(:c_info) { <<~INFO }
    3.0.0 a:= 1.0.0,b:~> 2.0|checksum:ccc1,ruby:>= 2.7.0,rubygems:>= 3.0.0
    3.3.3 a:>= 1.1.0,b:~> 2.0|checksum:ccc3,ruby:>= 3.0.0,rubygems:>= 3.2.3
  INFO

  describe "#available?" do
    it "returns true versions are available" do
      expect(parser).to be_available
    end

    it "returns false when versions are not available" do
      compact_index.versions = nil
      expect(parser).not_to be_available
    end
  end

  describe "#names" do
    it "returns the names" do
      expect(parser.names).to eq(%w[a b c])
    end

    it "returns an empty array when names is empty" do
      compact_index.names = ""
      expect(parser.names).to eq([])
    end

    it "returns an empty array when names is not readable" do
      compact_index.names = nil
      expect(parser.names).to eq([])
    end
  end

  describe "#versions" do
    it "returns the versions" do
      expect(parser.versions).to eq(
        "a" => [
          ["a", "1.0.0"],
          ["a", "1.0.1"],
          ["a", "1.1.0"],
        ],
        "b" => [
          ["b", "2.0.0"],
          ["b", "2.0.0", "java"],
        ],
        "c" => [
          ["c", "3.0.0"],
          ["c", "3.3.3"],
        ],
      )
    end

    it "returns an empty hash when versions is empty" do
      compact_index.versions = ""
      expect(parser.versions).to eq({})
    end

    it "returns an empty hash when versions is not readable" do
      compact_index.versions = nil
      expect(parser.versions).to eq({})
    end
  end

  describe "#info" do
    it "returns the info for example gem 'a' which has no deps" do
      expect(parser.info("a")).to eq(
        [
          [
            "a",
            "1.0.0",
            nil,
            [],
            [
              ["checksum", ["aaa1"]],
              ["ruby", [">= 3.0.0"]],
              ["rubygems", [">= 3.2.3"]],
            ],
          ],
          [
            "a",
            "1.0.1",
            nil,
            [],
            [
              ["checksum", ["aaa2"]],
              ["ruby", [">= 3.0.0"]],
              ["rubygems", [">= 3.2.3"]],
            ],
          ],
          [
            "a",
            "1.1.0",
            nil,
            [],
            [
              ["checksum", ["aaa3"]],
              ["ruby", [">= 3.0.0"]],
              ["rubygems", [">= 3.2.3"]],
            ],
          ],
        ]
      )
    end

    it "returns the info for example gem 'b' which has platform and compound deps" do
      expect(parser.info("b")).to eq(
        [
          [
            "b",
            "2.0.0",
            nil,
            [
              ["a", ["~> 1.0", "<= 3.0"]],
            ],
            [
              ["checksum", ["bbb1"]],
            ],
          ],
          [
            "b",
            "2.0.0",
            "java",
            [
              ["a", ["~> 1.0", "<= 3.0"]],
            ],
            [
              ["checksum", ["bbb2"]],
            ],
          ],
        ]
      )
    end

    it "returns the info for example gem 'c' which has deps and yanked version (requires use of correct info checksum)" do
      expect(parser.info("c")).to eq(
        [
          [
            "c",
            "3.0.0",
            nil,
            [
              ["a", ["= 1.0.0"]],
              ["b", ["~> 2.0"]],
            ],
            [
              ["checksum", ["ccc1"]],
              ["ruby", [">= 2.7.0"]],
              ["rubygems", [">= 3.0.0"]],
            ],
          ],
          [
            "c",
            "3.3.3",
            nil,
            [
              ["a", [">= 1.1.0"]],
              ["b", ["~> 2.0"]],
            ],
            [
              ["checksum", ["ccc3"]],
              ["ruby", [">= 3.0.0"]],
              ["rubygems", [">= 3.2.3"]],
            ],
          ],
        ]
      )
    end

    it "returns an empty array when the info is empty" do
      compact_index.set_info_data("a", {})
      expect(parser.info("a")).to eq([])
    end

    it "returns an empty array when the info is not readable" do
      expect(parser.info("d")).to eq([])
    end
  end
end
