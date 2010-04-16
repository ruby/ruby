require 'fileutils'

module RI
  class RiWriter

    def RiWriter.class_desc_path(dir, class_desc)
      File.join(dir, "cdesc-" + class_desc.name + ".yaml")
    end


    # Convert a name from internal form (containing punctuation)
    # to an external form (where punctuation is replaced
    # by %xx)

    def RiWriter.internal_to_external(name)
      name.gsub(/\W/) { sprintf("%%%02x", $&[0]) }
    end

    # And the reverse operation
    def RiWriter.external_to_internal(name)
      name.gsub(/%([0-9a-f]{2,2})/) { $1.to_i(16).chr }
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
      file_name = RiWriter.internal_to_external(method_desc.name)
      meth_file_name = File.join(dir, file_name)
      if method_desc.is_singleton
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
