for dir in ENV['PATH'].split(':')
  if File.exists? "#{dir}/wish"
    $CFLAGS = $CFLAGS + " -DWISHPATH=" + "'\"#{dir}/wish\"'"
    have_wish = TRUE
    break
  end
end

if have_wish and have_func('pipe')
  create_makefile("tkutil")
end
