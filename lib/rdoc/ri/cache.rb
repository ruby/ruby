require 'rdoc/ri'

class RDoc::RI::ClassEntry

  attr_reader :name
  attr_reader :path_names

  def initialize(path_name, name, in_class)
    @path_names = [ path_name ]
    @name = name
    @in_class = in_class
    @class_methods    = []
    @instance_methods = []
    @inferior_classes = []
  end

  # We found this class in more than one place, so add
  # in the name from there.
  def add_path(path)
    @path_names << path
  end

  # read in our methods and any classes
  # and modules in our namespace. Methods are
  # stored in files called name-c|i.yaml,
  # where the 'name' portion is the external
  # form of the method name and the c|i is a class|instance
  # flag

  def load_from(dir)
    Dir.foreach(dir) do |name|
      next if name =~ /^\./

      # convert from external to internal form, and
      # extract the instance/class flag

      if name =~ /^(.*?)-(c|i).yaml$/
        external_name = $1
        is_class_method = $2 == "c"
        internal_name = RDoc::RI::Writer.external_to_internal(external_name)
        list = is_class_method ? @class_methods : @instance_methods
        path = File.join(dir, name)
        list << RDoc::RI::MethodEntry.new(path, internal_name, is_class_method, self)
      else
        full_name = File.join(dir, name)
        if File.directory?(full_name)
          inf_class = @inferior_classes.find {|c| c.name == name }
          if inf_class
            inf_class.add_path(full_name)
          else
            inf_class = RDoc::RI::ClassEntry.new(full_name, name, self)
            @inferior_classes << inf_class
          end
          inf_class.load_from(full_name)
        end
      end
    end
  end

  # Return a list of any classes or modules that we contain
  # that match a given string

  def contained_modules_matching(name)
    @inferior_classes.find_all {|c| c.name[name]}
  end

  def classes_and_modules
    @inferior_classes
  end

  # Return an exact match to a particular name
  def contained_class_named(name)
    @inferior_classes.find {|c| c.name == name}
  end

  # return the list of local methods matching name
  # We're split into two because we need distinct behavior
  # when called from the _toplevel_
  def methods_matching(name, is_class_method)
    local_methods_matching(name, is_class_method)
  end

  # Find methods matching 'name' in ourselves and in
  # any classes we contain
  def recursively_find_methods_matching(name, is_class_method)
    res = local_methods_matching(name, is_class_method)
    @inferior_classes.each do |c|
      res.concat(c.recursively_find_methods_matching(name, is_class_method))
    end
    res
  end


  # Return our full name
  def full_name
    res = @in_class.full_name
    res << "::" unless res.empty?
    res << @name
  end

  # Return a list of all out method names
  def all_method_names
    res = @class_methods.map {|m| m.full_name }
    @instance_methods.each {|m| res << m.full_name}
    res
  end

  private

  # Return a list of all our methods matching a given string.
  # Is +is_class_methods+ if 'nil', we don't care if the method
  # is a class method or not, otherwise we only return
  # those methods that match
  def local_methods_matching(name, is_class_method)

    list = case is_class_method
           when nil then  @class_methods + @instance_methods
           when true then @class_methods
           when false then @instance_methods
           else fail "Unknown is_class_method: #{is_class_method.inspect}"
           end

    list.find_all {|m| m.name;  m.name[name]}
  end
end

##
# A TopLevelEntry is like a class entry, but when asked to search for methods
# searches all classes, not just itself

class RDoc::RI::TopLevelEntry < RDoc::RI::ClassEntry
  def methods_matching(name, is_class_method)
    res = recursively_find_methods_matching(name, is_class_method)
  end

  def full_name
      ""
  end

  def module_named(name)

  end

end

class RDoc::RI::MethodEntry
  attr_reader :name
  attr_reader :path_name

  def initialize(path_name, name, is_class_method, in_class)
    @path_name = path_name
    @name = name
    @is_class_method = is_class_method
    @in_class = in_class
  end

  def full_name
    res = @in_class.full_name
    unless res.empty?
      if @is_class_method
        res << "::"
      else
        res << "#"
      end
    end
    res << @name
  end
end

##
# We represent everything known about all 'ri' files accessible to this program

class RDoc::RI::Cache

  attr_reader :toplevel

  def initialize(dirs)
    # At the top level we have a dummy module holding the
    # overall namespace
    @toplevel = RDoc::RI::TopLevelEntry.new('', '::', nil)

    dirs.each do |dir|
      @toplevel.load_from(dir)
    end
  end

end
