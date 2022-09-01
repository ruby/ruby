# frozen_string_literal: true

require_relative "../spec_helper"

module SyntaxSuggest
  class CurrentIndex
    attr_reader :current_indent

    def initialize(value)
      @current_indent = value
    end

    def <=>(other)
      @current_indent <=> other.current_indent
    end

    def inspect
      @current_indent
    end
  end

  RSpec.describe CodeFrontier do
    it "works" do
      q = PriorityQueue.new
      q << 1
      q << 2
      expect(q.elements).to eq([2, 1])

      q << 3
      expect(q.elements).to eq([3, 1, 2])

      expect(q.pop).to eq(3)
      expect(q.pop).to eq(2)
      expect(q.pop).to eq(1)
      expect(q.pop).to eq(nil)

      array = []
      q = PriorityQueue.new
      array.reverse_each do |v|
        q << v
      end
      expect(q.elements).to eq(array)

      array = [100, 36, 17, 19, 25, 0, 3, 1, 7, 2]
      array.reverse_each do |v|
        q << v
      end

      expect(q.pop).to eq(100)
      expect(q.elements).to eq([36, 25, 19, 17, 0, 1, 7, 2, 3])

      # expected [36, 25, 19, 17, 0, 1, 7, 2, 3]
      expect(q.pop).to eq(36)
      expect(q.pop).to eq(25)
      expect(q.pop).to eq(19)
      expect(q.pop).to eq(17)
      expect(q.pop).to eq(7)
      expect(q.pop).to eq(3)
      expect(q.pop).to eq(2)
      expect(q.pop).to eq(1)
      expect(q.pop).to eq(0)
      expect(q.pop).to eq(nil)
    end

    it "priority queue" do
      frontier = PriorityQueue.new
      frontier << CurrentIndex.new(0)
      frontier << CurrentIndex.new(1)

      expect(frontier.sorted.map(&:current_indent)).to eq([0, 1])

      frontier << CurrentIndex.new(1)
      expect(frontier.sorted.map(&:current_indent)).to eq([0, 1, 1])

      frontier << CurrentIndex.new(0)
      expect(frontier.sorted.map(&:current_indent)).to eq([0, 0, 1, 1])

      frontier << CurrentIndex.new(10)
      expect(frontier.sorted.map(&:current_indent)).to eq([0, 0, 1, 1, 10])

      frontier << CurrentIndex.new(2)
      expect(frontier.sorted.map(&:current_indent)).to eq([0, 0, 1, 1, 2, 10])

      frontier = PriorityQueue.new
      values = [18, 18, 0, 18, 0, 18, 18, 18, 18, 16, 18, 8, 18, 8, 8, 8, 16, 6, 0, 0, 16, 16, 4, 14, 14, 12, 12, 12, 10, 12, 12, 12, 12, 8, 10, 10, 8, 8, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 8, 10, 6, 6, 6, 6, 6, 6, 8, 10, 8, 8, 10, 8, 10, 8, 10, 8, 6, 8, 8, 6, 8, 6, 6, 8, 0, 8, 0, 0, 8, 8, 0, 8, 0, 8, 8, 0, 8, 8, 8, 0, 8, 0, 8, 8, 8, 8, 8, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 8, 6, 8, 6, 6, 6, 6, 8, 6, 8, 6, 6, 4, 4, 6, 6, 4, 6, 4, 6, 6, 4, 6, 4, 4, 6, 6, 6, 6, 4, 4, 4, 2, 4, 4, 4, 4, 4, 4, 6, 6, 0, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 0, 0, 6, 6, 2]

      values.each do |v|
        value = CurrentIndex.new(v)
        frontier << value # CurrentIndex.new(v)
      end

      expect(frontier.sorted.map(&:current_indent)).to eq(values.sort)
    end
  end
end
