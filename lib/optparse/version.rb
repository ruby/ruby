# OptionParser internal utility

class << OptionParser
  def show_version(*pkg)
    progname = ARGV.options.program_name
    show = proc do |klass, version|
      version = version.join(".") if Array === version
      str = "#{progname}"
      str << ": #{klass}" unless klass == Object
      str << " version #{version}"
      case
      when klass.const_defined?(:Release)
        str << " (#{klass.const_get(:Release)})"
      when klass.const_defined?(:RELEASE)
        str << " (#{klass.const_get(:Release)})"
      end
      puts str
    end
    if pkg.size == 1 and pkg[0] == "all"
      self.search_const(::Object, /\AV(?:ERSION|ersion)\z/) do |klass, cname, version|
        unless cname[1] == ?e and klass.const_defined?(:Version)
          show.call(klass, version)
        end
      end
    else
      pkg.each do |pkg|
        /\A[A-Z]\w*((::|\/)[A-Z]\w*)*\z/ni =~ pkg or next
        begin
          pkg = eval(pkg)
          v = case
              when pkg.const_defined?(:Version)
                pkg.const_get(:Version)
              when pkg.const_defined?(:VERSION)
                pkg.const_get(:VERSION)
              else
                "unknown"
              end
          show.call(pkg, v)
        rescue NameError
          puts "#{progname}: #$!"
        end
      end
    end
    exit
  end

  def each_const(path, klass = ::Object)
    path.split(/::|\//).inject(klass) do |klass, name|
      raise NameError, path unless Module === klass
      klass.constants.grep(/#{name}/i) do |c|
        klass.const_defined?(c) or next
        c = klass.const_get(c)
      end
    end
  end

  def search_const(klass, name)
    klasses = [klass]
    while klass = klasses.shift
      klass.constants.each do |cname|
        klass.const_defined?(cname) or next
        const = klass.const_get(cname)
        yield klass, cname, const if name === cname
        klasses << const if Module === const and const != ::Object
      end
    end
  end
end
