# frozen_string_literal: false
module OpenSSL
  def self.check_func(func, header)
    have_func(func, header)
  end

  def self.check_func_or_macro(func, header)
    check_func(func, header) or
      have_macro(func, header) && $defs.push("-DHAVE_#{func.upcase}")
  end
end
