# frozen_string_literal: true
require "spec_helper"
require "bundler/yaml_serializer"

describe Bundler::YAMLSerializer do
  subject(:serializer) { Bundler::YAMLSerializer }

  describe "#dump" do
    it "works for simple hash" do
      hash = { "Q" => "Where does Thursday come before Wednesday? In the dictionary. :P" }

      expected = strip_whitespace <<-YAML
          ---
          Q: "Where does Thursday come before Wednesday? In the dictionary. :P"
      YAML

      expect(serializer.dump(hash)).to eq(expected)
    end

    it "handles nested hash" do
      hash = {
        "nice-one" => {
          "read_ahead" => "All generalizations are false, including this one",
        },
      }

      expected = strip_whitespace <<-YAML
          ---
          nice-one:
            read_ahead: "All generalizations are false, including this one"
      YAML

      expect(serializer.dump(hash)).to eq(expected)
    end

    it "array inside an hash" do
      hash = {
        "nested_hash" => {
          "contains_array" => [
            "Jack and Jill went up the hill",
            "To fetch a pail of water.",
            "Jack fell down and broke his crown,",
            "And Jill came tumbling after.",
          ],
        },
      }

      expected = strip_whitespace <<-YAML
        ---
        nested_hash:
          contains_array:
          - "Jack and Jill went up the hill"
          - "To fetch a pail of water."
          - "Jack fell down and broke his crown,"
          - "And Jill came tumbling after."
      YAML

      expect(serializer.dump(hash)).to eq(expected)
    end
  end

  describe "#load" do
    it "works for simple hash" do
      yaml = strip_whitespace <<-YAML
        ---
        Jon: "Air is free dude!"
        Jack: "Yes.. until you buy a bag of chips!"
      YAML

      hash = {
        "Jon" => "Air is free dude!",
        "Jack" => "Yes.. until you buy a bag of chips!",
      }

      expect(serializer.load(yaml)).to eq(hash)
    end

    it "works for nested hash" do
      yaml = strip_whitespace <<-YAML
        ---
        baa:
          baa: "black sheep"
          have: "you any wool?"
          yes: "merry have I"
        three: "bags full"
      YAML

      hash = {
        "baa" => {
          "baa" => "black sheep",
          "have" => "you any wool?",
          "yes" => "merry have I",
        },
        "three" => "bags full",
      }

      expect(serializer.load(yaml)).to eq(hash)
    end

    it "handles colon in key/value" do
      yaml = strip_whitespace <<-YAML
        BUNDLE_MIRROR__HTTPS://RUBYGEMS__ORG/: http://rubygems-mirror.org
      YAML

      expect(serializer.load(yaml)).to eq("BUNDLE_MIRROR__HTTPS://RUBYGEMS__ORG/" => "http://rubygems-mirror.org")
    end

    it "handles arrays inside hashes" do
      yaml = strip_whitespace <<-YAML
        ---
        nested_hash:
          contains_array:
          - "Why shouldn't you write with a broken pencil?"
          - "Because it's pointless!"
      YAML

      hash = {
        "nested_hash" => {
          "contains_array" => [
            "Why shouldn't you write with a broken pencil?",
            "Because it's pointless!",
          ],
        },
      }

      expect(serializer.load(yaml)).to eq(hash)
    end

    it "handles windows-style CRLF line endings" do
      yaml = strip_whitespace(<<-YAML).gsub("\n", "\r\n")
        ---
        nested_hash:
          contains_array:
          - "Why shouldn't you write with a broken pencil?"
          - "Because it's pointless!"
          - oh so silly
      YAML

      hash = {
        "nested_hash" => {
          "contains_array" => [
            "Why shouldn't you write with a broken pencil?",
            "Because it's pointless!",
            "oh so silly",
          ],
        },
      }

      expect(serializer.load(yaml)).to eq(hash)
    end
  end

  describe "against yaml lib" do
    let(:hash) do
      {
        "a_joke" => {
          "my-stand" => "I can totally keep secrets",
          "but" => "The people I tell them to can't :P",
        },
        "more" => {
          "first" => [
            "Can a kangaroo jump higher than a house?",
            "Of course, a house doesn't jump at all.",
          ],
          "second" => [
            "What did the sea say to the sand?",
            "Nothing, it simply waved.",
          ],
        },
        "sales" => {
          "item" => "A Parachute",
          "description" => "Only used once, never opened.",
        },
        "one-more" => "I'd tell you a chemistry joke but I know I wouldn't get a reaction.",
      }
    end

    context "#load" do
      it "retrieves the original hash" do
        require "yaml"
        expect(serializer.load(YAML.dump(hash))).to eq(hash)
      end
    end

    context "#dump" do
      it "retrieves the original hash" do
        require "yaml"
        expect(YAML.load(serializer.dump(hash))).to eq(hash)
      end
    end
  end
end
