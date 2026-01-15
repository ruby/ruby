# frozen_string_literal: true

# This builder creates extensions defined using CMake. Its is invoked if a Gem's spec file
# sets the `extension` property to a string that contains `CMakeLists.txt`.
#
# In general, CMake projects are built in two steps:
#
#  * configure
#  * build
#
# The builder follow this convention. First it runs a configuration step and then it runs a build step.
#
# CMake projects can be quite configurable - it is likely you will want to specify options when
# installing a gem. To pass options to CMake specify them after `--` in the gem install command. For example:
#
#   gem install <gem_name> -- --preset <preset_name>
#
# Note that options are ONLY sent to the configure step - it is not currently possible to specify
# options for the build step. If this becomes and issue then the CMake builder can be updated to
# support build options.
#
# Useful options to know are:
#
#  -G to specify a generator (-G Ninja is recommended)
#  -D<CMAKE_VARIABLE> to set a CMake variable (for example -DCMAKE_BUILD_TYPE=Release)
#  --preset <preset_name> to use a preset
#
# If the Gem author provides presets, via CMakePresets.json file, you will likely want to use one of them.
# If not, you may wish to specify a generator. Ninja is recommended because it can build projects in parallel
# and thus much faster than building them serially like Make does.

class Gem::Ext::CmakeBuilder < Gem::Ext::Builder
  attr_accessor :runner, :profile
  def initialize
    @runner = self.class.method(:run)
    @profile = :release
  end

  def build(extension, dest_path, results, args = [], lib_dir = nil, cmake_dir = Dir.pwd,
    target_rbconfig = Gem.target_rbconfig, n_jobs: nil)
    if target_rbconfig.path
      warn "--target-rbconfig is not yet supported for CMake extensions. Ignoring"
    end

    # Figure the build dir
    build_dir = File.join(cmake_dir, "build")

    # Check if the gem defined presets
    check_presets(cmake_dir, args, results)

    # Configure
    configure(cmake_dir, build_dir, dest_path, args, results)

    # Compile
    compile(cmake_dir, build_dir, args, results)

    results
  end

  def configure(cmake_dir, build_dir, install_dir, args, results)
    cmd = ["cmake",
           cmake_dir,
           "-B",
           build_dir,
           "-DCMAKE_RUNTIME_OUTPUT_DIRECTORY=#{install_dir}", # Windows
           "-DCMAKE_LIBRARY_OUTPUT_DIRECTORY=#{install_dir}", # Not Windows
           *Gem::Command.build_args,
           *args]

    runner.call(cmd, results, "cmake_configure", cmake_dir)
  end

  def compile(cmake_dir, build_dir, args, results)
    cmd = ["cmake",
           "--build",
           build_dir.to_s,
           "--config",
           @profile.to_s]

    runner.call(cmd, results, "cmake_compile", cmake_dir)
  end

  private

  def check_presets(cmake_dir, args, results)
    # Return if the user specified a preset
    return unless args.grep(/--preset/i).empty?

    cmd = ["cmake",
           "--list-presets"]

    presets = Array.new
    begin
      runner.call(cmd, presets, "cmake_presets", cmake_dir)

      # Remove the first two lines of the array which is the current_directory and the command
      # that was run
      presets = presets[2..].join
      results << <<~EOS
        The gem author provided a list of presets that can be used to build the gem. To use a preset specify it on the command line:

          gem install <gem_name> -- --preset <preset_name>

        #{presets}
      EOS
    rescue Gem::InstallError
      # Do nothing, CMakePresets.json was not included in the Gem
    end
  end
end
