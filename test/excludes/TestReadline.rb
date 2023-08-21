# frozen_string_literal: false
if /mingw/i.match?(RUBY_PLATFORM)
  exclude(:test_input_metachar_multibyte, "failed with readline.so on MiNGW")
end
