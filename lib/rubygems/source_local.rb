require 'rubygems/source'

class Gem::Source::Local < Gem::Source
  def initialize
    @uri = nil
  end

  def load_specs(type)
    names = []

    @specs = {}

    Dir["*.gem"].each do |file|
      begin
        pkg = Gem::Package.new(file)
      rescue SystemCallError, Gem::Package::FormatError
        # ignore
      else
        tup = pkg.spec.name_tuple
        @specs[tup] = [File.expand_path(file), pkg]

        case type
        when :released
          unless pkg.spec.version.prerelease?
            names << pkg.spec.name_tuple
          end
        when :prerelease
          if pkg.spec.version.prerelease?
            names << pkg.spec.name_tuple
          end
        when :latest
          tup = pkg.spec.name_tuple

          cur = names.find { |x| x.name == tup.name }
          if !cur
            names << tup
          elsif cur.version < tup.version
            names.delete cur
            names << tup
          end
        else
          names << pkg.spec.name_tuple
        end
      end
    end

    names
  end

  def find_gem(gem_name, version=Gem::Requirement.default,
               prerelease=false)
    load_specs :complete

    found = []

    @specs.each do |n, data|
      if n.name == gem_name
        s = data[1].spec

        if version.satisfied_by?(s.version)
          if prerelease
            found << s
          elsif !s.version.prerelease?
            found << s
          end
        end
      end
    end

    found.sort_by { |s| s.version }.last
  end

  def fetch_spec(name)
    load_specs :complete

    if data = @specs[name]
      data.last.spec
    else
      raise Gem::Exception, "Unable to find spec for '#{name}'"
    end
  end

  def download(spec, cache_dir=nil)
    load_specs :complete

    @specs.each do |name, data|
      return data[0] if data[1].spec == spec
    end

    raise Gem::Exception, "Unable to find file for '#{spec.full_name}'"
  end
end
