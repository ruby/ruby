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
    have_func(func, header, deprecated_warning_flag) and
      have_header(header, nil, deprecated_warning_flag)
  end
end
