# OptionParser internal utility

class << OptionParser
  def show_version(*pkg)
    progname = ARGV.options.program_name
    show = proc do |klass, version|
      version = version.join(".") if Array === version
      str = "#{progname}: #{klass} version #{version}"
      if klass.const_defined?(:Release)
        str << " (#{klass.const_get(:Release)})"
      end
      puts str
    end
    if pkg.size == 1 and pkg[0] == "all"
      self.search_const(::Object, "Version", &show)
    else
      pkg.each do |pkg|
        /\A[A-Z]\w*((::|\/)[A-Z]\w*)*\z/ni =~ pkg or next
        begin
          pkg = eval(pkg)
          show.call(pkg, pkg.const_defined?(:Version) ? pkg.const_get(:Version) : "unknown")
        rescue NameError
          puts "#{progname}: #$!"
        end
      end
    end
    exit
  end

  def search_const(klass, name)
    klasses = [klass]
    while klass = klasses.shift
      klass.constants.each do |cname|
        klass.const_defined?(cname) or next
        const = klass.const_get(cname)
        yield klass, const if cname == name
        klasses << const if Module === const and const != ::Object
      end
    end
  end
end
