if RUBY_PLATFORM.include?("mingw")
  reason = <<~EOS
  Mingw crt-git 12.0.0.r369.g0d4221712-1 now prohibits "command line
  contains characters that are not supported in the active code page".
  https://sourceforge.net/p/mingw-w64/mingw-w64/ci/0d42217123d3aec0341b79f6d959c76e09648a1e/
  EOS

  exclude(:test_chdir, reason)
  exclude(:test_locale_codepage, reason)
  exclude(:test_command_line_progname_nonascii, reason)
end
