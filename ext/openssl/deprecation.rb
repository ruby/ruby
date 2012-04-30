module OpenSSL
  def self.check_func(func, header)
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
    have_func(func, header, flag)
  end
end
