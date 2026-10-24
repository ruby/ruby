# frozen_string_literal: false
require 'test/unit'

class TestInsnsLeaf < Test::Unit::TestCase
  require "set"

  class Id
    attr_reader :db_id
    def initialize(db_id)
      @db_id = db_id
    end

    def ==(other)
      other.class == self.class && other.db_id == db_id
    end
    alias_method :eql?, :==

    def hash
      10
    end

    def <=>(other)
      db_id <=> other.db_id if other.is_a?(self.class)
    end
  end

  class Namespace
    IDS = Set[
      Id.new(1).freeze,
      Id.new(2).freeze,
      Id.new(3).freeze,
      Id.new(4).freeze,
    ].freeze

    class << self
      def test?(id)
	IDS.include?(id)
      end
    end
  end

  def test_insns_leaf
    assert Namespace.test?(Id.new(1)), "IDS should include 1"
    assert !Namespace.test?(Id.new(5)), "IDS should not include 5"
  end

  def test_intern_is_not_leaf
    assert_separately([], <<~'RUBY')
      class EncodingError
        def initialize(...)
          $encoding_error_initialize_called = true
          super
        end
      end

      invalid_utf8 = (+"\xFF").force_encoding(Encoding::UTF_8)
      assert_raise(EncodingError) { :"#{invalid_utf8}" }
      assert $encoding_error_initialize_called
    RUBY
  end
end
