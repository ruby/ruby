# frozen_string_literal: true

require_relative "../spec_helper"

module SyntaxSuggest
  RSpec.describe "EndBlockParse" do
    it "finds blocks based on `end` keyword" do
      source = <<~EOM
        describe "cat" # 1
          Cat.call do  # 2
          end          # 3
        end            # 4
                       # 5
        it "dog" do    # 6
          Dog.call do  # 7
          end          # 8
        end            # 9
      EOM

      lex = LexAll.new(source: source)
      expect(lex.map(&:token).to_s).to include("dog")
      expect(lex.first.line).to eq(1)
      expect(lex.last.line).to eq(9)
    end
  end
end
