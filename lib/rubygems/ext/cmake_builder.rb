# frozen_string_literal: true

class Gem::Ext::CmakeBuilder < Gem::Ext::Builder
  def self.build(extension, dest_path, results, args=[], lib_dir=nil, cmake_dir=Dir.pwd,
    target_rbconfig=Gem.target_rbconfig)
    if target_rbconfig.path
      warn "--target-rbconfig is not yet supported for CMake extensions. Ignoring"
    end

    unless File.exist?(File.join(cmake_dir, "Makefile"))
      require_relative "../command"
      cmd = ["cmake", ".", "-DCMAKE_INSTALL_PREFIX=#{dest_path}", *Gem::Command.build_args]

      run cmd, results, class_name, cmake_dir
    end

    make dest_path, results, cmake_dir, target_rbconfig: target_rbconfig

    results
  end
end
