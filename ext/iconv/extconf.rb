require 'mkmf'

dir_config("iconv")

conf = File.exist?(File.join($srcdir, "config.charset"))
conf = with_config("config-charset", enable_config("config-charset", conf))

if have_func("iconv", "iconv.h") or
    have_library("iconv", "iconv") {|s| s.sub(/(?=\n\/\*top\*\/)/, "#include <iconv.h>")}
  if checking_for("const of iconv() 2nd argument") do
      create_tmpsrc(cpp_include("iconv.h") + "---> iconv(cd,0,0,0,0) <---")
      src = xpopen(cpp_command("")) {|f|f.read}
      if !(func = src[/^--->\s*(\w+).*\s*<---/, 1])
        Logging::message "iconv function name not found"
        false
      elsif !(second = src[%r"\b#{func}\s*\(.*?,(.*?),.*?\)\s*;"m, 1])
        Logging::message "prototype for #{func}() not found"
        false
      else
        Logging::message $&+"\n"
        /\bconst\b/ =~ second
      end
    end
    $defs.push('-DICONV_INPTR_CAST=""')
  else
    $defs.push('-DICONV_INPTR_CAST="(char **)"')
  end
  if conf
    prefix = '$(srcdir)'
    prefix =  $nmake ? "{#{prefix}}" : "#{prefix}/"
    wrapper = "./iconv.rb"
    $INSTALLFILES = [[wrapper, "$(RUBYARCHDIR)"]]
    if String === conf
      require 'uri'
      scheme = URI.parse(conf).scheme
    else
      conf = prefix + "config.charset"
    end
    $cleanfiles << wrapper
  end
  create_makefile("iconv")
  if conf
    open("Makefile", "a") do |mf|
      mf.print("\nall: #{wrapper}\n\n#{wrapper}: #{prefix}charset_alias.rb")
      mf.print(" ", conf) unless scheme
      mf.print("\n\t$(RUBY) ", prefix, "charset_alias.rb ", conf, " $@\n")
    end
  end
end
