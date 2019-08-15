class ProfileFilter
  def initialize(what, *files)
    @what = what
    @methods = load(*files)
    @pattern = /([^ .#]+[.#])([^ ]+)/
  end

  def find(name)
    return name if File.exist?(File.expand_path(name))

    ["spec/profiles", "spec", "profiles", "."].each do |dir|
      file = File.join dir, name
      return file if File.exist? file
    end
  end

  def parse(file)
    pattern = /(\S+):\s*/
    key = ""
    file.inject(Hash.new { |h,k| h[k] = [] }) do |hash, line|
      line.chomp!
      if line[0,2] == "- "
        hash[key] << line[2..-1].gsub(/[ '"]/, "")
      elsif m = pattern.match(line)
        key = m[1]
      end
      hash
    end
  end

  def load(*files)
    files.inject({}) do |hash, file|
      next hash unless name = find(file)

      File.open name, "r" do |f|
        hash.merge parse(f)
      end
    end
  end

  def ===(string)
    return false unless m = @pattern.match(string)
    return false unless l = @methods[m[1]]
    l.include? m[2]
  end

  def register
    MSpec.register @what, self
  end

  def unregister
    MSpec.unregister @what, self
  end
end
