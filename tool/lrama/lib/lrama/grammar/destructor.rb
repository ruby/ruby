# frozen_string_literal: true

module Lrama
  class Grammar
    class Destructor < Struct.new(:ident_or_tags, :token_code, :lineno, keyword_init: true)
      def translated_code(tag)
        Code::DestructorCode.new(type: :destructor, token_code: token_code, tag: tag).translated_code
      end
    end
  end
end
