module RI

  class ClassEntry

    attr_reader :name
    attr_reader :path_name
    
    def initialize(path_name, name, in_class)
      @path_name = path_name
      @name = name
      @in_class = in_class
      @class_methods    = []
      @instance_methods = []
      @inferior_classes = []
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
          internal_name = external_name
          list = is_class_method ? @class_methods : @instance_methods
          path = File.join(dir, name)
          list << MethodEntry.new(path, internal_name, is_class_method, self)
        else
          full_name = File.join(dir, name)
          if File.directory?(full_name)
            inf_class = ClassEntry.new(full_name, name, self)
            inf_class.load_from(full_name)
            @inferior_classes << inf_class
          end
        end
      end
    end

    # Return a list of any classes or modules that we contain
    # that match a given string

    def contained_modules_matching(name)
      @inferior_classes.find_all {|c| c.name[name]}
    end

    # return the list of local methods matching name
    # We're split into two because we need distinct behavior
    # when called from the toplevel
    def methods_matching(name)
      local_methods_matching(name)
    end

    # Find methods matching 'name' in ourselves and in
    # any classes we contain
    def recursively_find_methods_matching(name)
      res = local_methods_matching(name)
      @inferior_classes.each do |c|
        res.concat(c.recursively_find_methods_matching(name))
      end
      res
    end


    # Return our full name
    def full_name
      res = @in_class.full_name
      res << "::" unless res.empty?
      res << @name
    end

    private

    # Return a list of all our methods matching a given string
    def local_methods_matching(name)
      @class_methods.find_all {|m| m.name[name] } +
                                                   @instance_methods.find_all {|m| m.name[name] }
    end
  end

  # A TopLevelEntry is like a class entry, but when asked to search
  # for methods searches all classes, not just itself

  class TopLevelEntry < ClassEntry
    def methods_matching(name)
      res = recursively_find_methods_matching(name)
    end

    def full_name
      ""
    end
  end

  class MethodEntry
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

  # We represent everything know about all 'ri' files
  # accessible to this program

  class RiCache

    attr_reader :toplevel

    def initialize(dirs)
      # At the top level we have a dummy module holding the
      # overall namespace
      @toplevel = TopLevelEntry.new('', '::', nil)

      dirs.each do |dir|
        @toplevel.load_from(dir)
      end
    end

  end
end
