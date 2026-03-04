# frozen_string_literal: true

require_relative "../spec_helper"

module SyntaxSuggest
  RSpec.describe "MiniStringIO" do
    it "#puts with no inputs" do
      io = MiniStringIO.new
      io.puts
      expect(io.string).to eq($/)
    end

    it "#puts with an input" do
      io = MiniStringIO.new
      io.puts "Hello"
      expect(io.string).to eq(["Hello", $/].join)
    end

    it "#puts with an input with a newline" do
      io = MiniStringIO.new
      io.puts "Hello\n"
      expect(io.string).to eq(["Hello\n", $/].join)
    end
  end
end
