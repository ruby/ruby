class Gem::AvailableSet
  Tuple = Struct.new(:spec, :source)

  def initialize
    @set = []
    @sorted = nil
  end

  attr_reader :set

  def add(spec, source)
    @set << Tuple.new(spec, source)
    @sorted = nil
    self
  end

  def <<(o)
    case o
    when Gem::AvailableSet
      s = o.set
    when Array
      s = o.map do |sp,so|
        if !sp.kind_of?(Gem::Specification) or !so.kind_of?(Gem::Source)
          raise TypeError, "Array must be in [[spec, source], ...] form"
        end

        Tuple.new(sp,so)
      end
    else
      raise TypeError, "must be a Gem::AvailableSet"
    end

    @set += s
    @sorted = nil

    self
  end

  def empty?
    @set.empty?
  end

  def all_specs
    @set.map { |t| t.spec }
  end

  def match_platform!
    @set.reject! { |t| !Gem::Platform.match(t.spec.platform) }
    @sorted = nil
    self
  end

  def sorted
    @sorted ||= @set.sort do |a,b|
      i = b.spec <=> a.spec
      i != 0 ? i : (a.source <=> b.source)
    end
  end

  def size
    @set.size
  end

  def source_for(spec)
    f = @set.find { |t| t.spec == spec }
    f.source
  end

  def pick_best!
    return self if empty?

    @set = [sorted.first]
    @sorted = nil
    self
  end

  def remove_installed!(dep)
    @set.reject! do |t|
      # already locally installed
      Gem::Specification.any? do |installed_spec|
        dep.name == installed_spec.name and
          dep.requirement.satisfied_by? installed_spec.version
      end
    end

    @sorted = nil
    self
  end

  def inject_into_list(dep_list)
    @set.each { |t| dep_list.add t.spec }
  end
end
