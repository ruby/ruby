require 'rdoc/ri/ri_descriptions'
require 'rdoc/ri/ri_writer'
require 'rdoc/markup/simple_markup/to_flow'

module RI
  class RiReader

    def initialize(ri_cache)
      @cache = ri_cache
    end

    def top_level_namespace
      [ @cache.toplevel ]
    end

    def lookup_namespace_in(target, namespaces)
      result = []
      for n in namespaces
        result.concat(n.contained_modules_matching(target))
      end
      result
    end

    def find_class_by_name(full_name)
      names = full_name.split(/::/)
      ns = @cache.toplevel
      for name in names
        ns = ns.contained_class_named(name)
        return nil if ns.nil?
      end
      get_class(ns)
    end

    def find_methods(name, is_class_method, namespaces)
      result = []
      namespaces.each do |ns|
        result.concat ns.methods_matching(name, is_class_method)
      end
      result
    end

    # return the MethodDescription for a given MethodEntry
    # by deserializing the YAML
    def get_method(method_entry)
      path = method_entry.path_name
      File.open(path) { |f| RI::Description.deserialize(f) }
    end

    # Return a class description
    def get_class(class_entry)
      result = nil
      for path in class_entry.path_names
        path = RiWriter.class_desc_path(path, class_entry)
        desc = File.open(path) {|f| RI::Description.deserialize(f) }
        if result
          result.merge_in(desc)
        else
          result = desc
        end
      end
      result
    end

    # return the names of all classes and modules
    def full_class_names
      res = []
      find_classes_in(res, @cache.toplevel)
    end

    # return a list of all classes, modules, and methods
    def all_names
      res = []
      find_names_in(res, @cache.toplevel)
    end

    # ----
    private
    # ----

    def find_classes_in(res, klass)
      classes = klass.classes_and_modules
      for c in classes
        res << c.full_name
        find_classes_in(res, c)
      end
      res
    end

    def find_names_in(res, klass)
      classes = klass.classes_and_modules
      for c in classes
        res << c.full_name
        res.concat c.all_method_names
        find_names_in(res, c)
      end
      res
    end

  end
end
