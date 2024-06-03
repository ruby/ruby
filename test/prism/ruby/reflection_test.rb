# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class ReflectionTest < TestCase
    def test_fields_for
      fields = Reflection.fields_for(CallNode)
      methods = CallNode.instance_methods(false)

      fields.each do |field|
        if field.is_a?(Reflection::FlagsField)
          field.flags.each do |flag|
            assert_includes methods, flag
          end
        else
          assert_includes methods, field.name
        end
      end
    end
  end
end
