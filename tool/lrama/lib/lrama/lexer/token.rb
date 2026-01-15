# rbs_inline: enabled
# frozen_string_literal: true

require_relative 'token/base'
require_relative 'token/char'
require_relative 'token/empty'
require_relative 'token/ident'
require_relative 'token/instantiate_rule'
require_relative 'token/int'
require_relative 'token/str'
require_relative 'token/tag'
require_relative 'token/token'
require_relative 'token/user_code'

module Lrama
  class Lexer
    module Token
    end
  end
end
