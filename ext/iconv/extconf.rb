require 'mkmf'

dir_config("iconv")

conf = File.exist?(File.join($srcdir, "config.charset"))
conf = with_config("config-charset", enable_config("config-charset", conf))

if have_header("iconv.h")
  have_library("iconv")
  if conf
    prefix = '$(srcdir)'
    prefix =  $nmake ? "{#{prefix}}" : "#{prefix}/"
    $INSTALLFILES = [["./iconv.rb", "$(RUBYLIBDIR)"]]
    if String === conf
      require 'uri'
      scheme = URI.parse(conf).scheme
    else
      conf = prefix + "config.charset"
    end
  end
  create_makefile("iconv")
  if conf
    open("Makefile", "a") do |mf|
      mf.print("\nall: iconv.rb\n\niconv.rb: ", prefix, "charset_alias.rb")
      mf.print(" ", conf) unless scheme
      mf.print("\n\t$(RUBY) ", prefix, "charset_alias.rb ", conf, " $@\n")
    end
  end
end
