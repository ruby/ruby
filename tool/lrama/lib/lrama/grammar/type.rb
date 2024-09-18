# frozen_string_literal: true

module Lrama
  class Grammar
    class Type
      attr_reader :id, :tag

      def initialize(id:, tag:)
        @id = id
        @tag = tag
      end

      def ==(other)
        self.class == other.class &&
        self.id == other.id &&
        self.tag == other.tag
      end
    end
  end
end
