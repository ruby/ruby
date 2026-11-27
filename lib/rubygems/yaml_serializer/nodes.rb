# frozen_string_literal: true

module Gem
  module YAMLSerializer
    Scalar = Struct.new(:value, :tag, :anchor)
    Mapping = Struct.new(:pairs, :tag, :anchor)
    Sequence = Struct.new(:items, :tag, :anchor)
    AliasRef = Struct.new(:name)
  end
end
