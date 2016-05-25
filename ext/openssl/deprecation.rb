# frozen_string_literal: false
module OpenSSL
  def self.deprecated_warning_flag
    unless flag = (@deprecated_warning_flag ||= nil)
      if try_compile("", flag = "-Werror=deprecated-declarations")
        if with_config("broken-apple-openssl")
          flag = "-Wno-deprecated-declarations"
        end
        $warnflags << " #{flag}"
      else
        flag = ""
      end
      @deprecated_warning_flag = flag
    end
    flag
  end

  def self.check_func(func, header)
    have_func(func, header, deprecated_warning_flag)
  end

  def self.check_func_or_macro(func, header)
    check_func(func, header) or
      have_macro(func, header) && $defs.push("-DHAVE_#{func.upcase}")
  end
end
