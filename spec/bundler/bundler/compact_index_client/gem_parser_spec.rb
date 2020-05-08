# frozen_string_literal: true

require "bundler/compact_index_client/gem_parser"

RSpec.describe Bundler::CompactIndexClient::GemParser do
  def parse(line)
    parser = Bundler::CompactIndexClient::GemParser.new
    parser.parse(line)
  end

  context "platform" do
    it "existent" do
      checksum = "d5956d2bcb509af2cd07c90d9e5fdb331be8845a75bfd823a31c147b52cff471"
      line = "1.11.3-java |checksum:#{checksum}"
      expected = [
        "1.11.3",
        "java",
        [],
        [
          ["checksum", [checksum]],
        ],
      ]
      expect(parse(line)).to eq expected
    end

    it "nonexistent" do
      checksum = "6da2eb3c4867e64df28d3e0b1008422dfacda7c046f9a8f3c56c52505b195e81"
      line = "1.11.3 |checksum:#{checksum}"
      expected = [
        "1.11.3",
        nil,
        [],
        [
          ["checksum", [checksum]],
        ],
      ]
      expect(parse(line)).to eq expected
    end
  end

  context "dependencies" do
    it "nothing" do
      checksum = "6da2eb3c4867e64df28d3e0b1008422dfacda7c046f9a8f3c56c52505b195e81"
      line = "1.11.3 |checksum:#{checksum}"
      expected = [
        "1.11.3",
        nil,
        [],
        [
          ["checksum", [checksum]],
        ],
      ]
      expect(parse(line)).to eq expected
    end

    it "one" do
      checksum = "5f0b378d12ab5665e2b6a1525274de97350238963002583cf088dae988527647"
      line = "0.3.2 bones:>= 2.4.2|checksum:#{checksum}"
      expected = [
        "0.3.2",
        nil,
        [
          ["bones", [">= 2.4.2"]],
        ],
        [
          ["checksum", [checksum]],
        ],
      ]
      expect(parse(line)).to eq expected
    end

    it "multiple" do
      checksum = "199e892ada86c44d1f2e110b822d5da46b52fa2cbd2f00d89695b4cf610f9927"
      line = "3.1.2 native-package-installer:>= 0,pkg-config:>= 0|checksum:#{checksum}"
      expected = [
        "3.1.2",
        nil,
        [
          ["native-package-installer", [">= 0"]],
          ["pkg-config", [">= 0"]],
        ],
        [
          ["checksum", [checksum]],
        ],
      ]
      expect(parse(line)).to eq expected
    end

    context "version" do
      it "multiple" do
        checksum = "1ec894b8090cb2c9393153552be2f3b6b1975265cbc1e0a3c6b28ebfea7e76a1"
        line = "3.1.5 multi_json:< 1.3&>= 1.0|checksum:#{checksum}"
        expected = [
          "3.1.5",
          nil,
          [
            ["multi_json", ["< 1.3", ">= 1.0"]],
          ],
          [
            ["checksum", [checksum]],
          ],
        ]
        expect(parse(line)).to eq expected
      end
    end
  end

  context "requirements" do
    context "ruby" do
      it "one version" do
        checksum ="6da2eb3c4867e64df28d3e0b1008422dfacda7c046f9a8f3c56c52505b195e81"
        line = "1.11.3 |checksum:#{checksum},ruby:>= 2.0"
        expected = [
          "1.11.3",
          nil,
          [],
          [
            ["checksum", [checksum]],
            ["ruby", [">= 2.0"]],
          ],
        ]
        expect(parse(line)).to eq expected
      end

      it "multiple versions" do
        checksum = "99e4845796c8dec1c3fc80dc772860a01633b33291bd7534007f5c7724f0b876"
        line = "1.11.3-x86-mingw32 |checksum:#{checksum},ruby:>= 2.2, < 2.7.dev"
        expected = [
          "1.11.3",
          "x86-mingw32",
          [],
          [
            ["checksum", [checksum]],
            ["ruby", [">= 2.2", "< 2.7.dev"]],
          ],
        ]
        expect(parse(line)).to eq expected
      end

      it "with rubygems" do
        checksum = "7a82b358f00da749b01f8c84df8e8eb21c1bc389740aab9a2bf4ce59894564ac"
        line = "1.9.23.pre1 |checksum:#{checksum},ruby:>= 1.9, < 2.7.dev,rubygems:> 1.3.1"
        expected = [
          "1.9.23.pre1",
          nil,
          [],
          [
            ["checksum", [checksum]],
            ["ruby", [">= 1.9", "< 2.7.dev"]],
            ["rubygems", ["> 1.3.1"]],
          ],
        ]
        expect(parse(line)).to eq expected
      end
    end

    context "rubygems" do
      it "existent" do
        checksum = "91ddb4c1b5482a4aff957f6733e282ce2767b2d3051138e0203e39d6df4eba10"
        line = "1.0.12.pre |checksum:#{checksum},rubygems:> 1.3.1"
        expected = [
          "1.0.12.pre",
          nil,
          [],
          [
            ["checksum", [checksum]],
            ["rubygems", ["> 1.3.1"]],
          ],
        ]
        expect(parse(line)).to eq expected
      end
    end
  end
end
