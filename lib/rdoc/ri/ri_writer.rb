require 'fileutils'

module RI
  class RiWriter

    def RiWriter.class_desc_path(dir, class_desc)
      File.join(dir, "cdesc-" + class_desc.name + ".yaml")
    end

    
    def initialize(base_dir)
      @base_dir = base_dir
    end

    def remove_class(class_desc)
      FileUtils.rm_rf(path_to_dir(class_desc.full_name))
    end

    def add_class(class_desc)
      dir = path_to_dir(class_desc.full_name)
      FileUtils.mkdir_p(dir)
      class_file_name = RiWriter.class_desc_path(dir, class_desc)
      File.open(class_file_name, "w") do |f|
        f.write(class_desc.serialize)
      end
    end

    def add_method(class_desc, method_desc)
      dir = path_to_dir(class_desc.full_name)
      meth_file_name = File.join(dir, method_desc.name)
      if method_desc.is_class_method
        meth_file_name += "-c.yaml"
      else
        meth_file_name += "-i.yaml"
      end

      File.open(meth_file_name, "w") do |f|
        f.write(method_desc.serialize)
      end
    end

    private

    def path_to_dir(class_name)
      File.join(@base_dir, *class_name.split('::'))
    end
  end
end
