# frozen_string_literal: true

# This class is used by rubygems to build Rust extensions. It is a thin-wrapper
# over the `cargo rustc` command which takes care of building Rust code in a way
# that Ruby can use.
class Gem::Ext::CargoBuilder < Gem::Ext::Builder
  attr_accessor :spec, :runner, :profile

  def initialize
    require_relative "../command"
    require_relative "cargo_builder/link_flag_converter"

    @runner = self.class.method(:run)
    @profile = :release
  end

  def build(_extension, dest_path, results, args = [], lib_dir = nil, cargo_dir = Dir.pwd)
    require "tempfile"
    require "fileutils"

    # Where's the Cargo.toml of the crate we're building
    cargo_toml = File.join(cargo_dir, "Cargo.toml")
    # What's the crate's name
    crate_name = cargo_crate_name(cargo_dir, cargo_toml, results)

    begin
      # Create a tmp dir to do the build in
      tmp_dest = Dir.mktmpdir(".gem.", cargo_dir)

      # Run the build
      cmd = cargo_command(cargo_toml, tmp_dest, args, crate_name)
      runner.call(cmd, results, "cargo", cargo_dir, build_env)

      # Where do we expect Cargo to write the compiled library
      dylib_path = cargo_dylib_path(tmp_dest, crate_name)

      # Helpful error if we didn't find the compiled library
      raise DylibNotFoundError, tmp_dest unless File.exist?(dylib_path)

      # Cargo and Ruby differ on how the library should be named, rename from
      # what Cargo outputs to what Ruby expects
      dlext_name = "#{crate_name}.#{makefile_config("DLEXT")}"
      dlext_path = File.join(File.dirname(dylib_path), dlext_name)
      FileUtils.cp(dylib_path, dlext_path)

      # TODO: remove in RubyGems 4
      if Gem.install_extension_in_lib && lib_dir
        FileUtils.mkdir_p lib_dir
        p [dlext_path, lib_dir]
        FileUtils.cp_r dlext_path, lib_dir, remove_destination: true
      end

      # move to final destination
      FileUtils.mkdir_p dest_path
      FileUtils.cp_r dlext_path, dest_path, remove_destination: true
    ensure
      # clean up intermediary build artifacts
      FileUtils.rm_rf tmp_dest if tmp_dest
    end

    results
  end

  def build_env
    build_env = rb_config_env
    build_env["RUBY_STATIC"] = "true" if ruby_static? && ENV.key?("RUBY_STATIC")
    cfg = "--cfg=rb_sys_gem --cfg=rubygems --cfg=rubygems_#{Gem::VERSION.tr(".", "_")}"
    build_env["RUSTFLAGS"] = [ENV["RUSTFLAGS"], cfg].compact.join(" ")
    build_env
  end

  def cargo_command(cargo_toml, dest_path, args = [], crate_name = nil)
    require "shellwords"

    cmd = []
    cmd += [cargo, "rustc"]
    cmd += ["--crate-type", "cdylib"]
    cmd += ["--target", ENV["CARGO_BUILD_TARGET"]] if ENV["CARGO_BUILD_TARGET"]
    cmd += ["--target-dir", dest_path]
    cmd += ["--manifest-path", cargo_toml]
    cmd += ["--lib"]
    cmd += ["--profile", profile.to_s]
    cmd += ["--locked"]
    cmd += Gem::Command.build_args
    cmd += args
    cmd += ["--"]
    cmd += [*cargo_rustc_args(dest_path, crate_name)]
    cmd
  end

  private

  def cargo
    ENV.fetch("CARGO", "cargo")
  end

  def rb_config_env
    result = {}
    RbConfig::CONFIG.each {|k, v| result["RBCONFIG_#{k}"] = v }
    result
  end

  def cargo_rustc_args(dest_dir, crate_name)
    [
      *linker_args,
      *mkmf_libpath,
      *rustc_dynamic_linker_flags(dest_dir, crate_name),
      *rustc_lib_flags(dest_dir),
      *platform_specific_rustc_args(dest_dir),
    ]
  end

  def platform_specific_rustc_args(dest_dir, flags = [])
    if mingw_target?
      # On mingw platforms, mkmf adds libruby to the linker flags
      flags += libruby_args(dest_dir)

      # Make sure ALSR is used on mingw
      # see https://github.com/rust-lang/rust/pull/75406/files
      flags += ["-C", "link-arg=-Wl,--dynamicbase"]
      flags += ["-C", "link-arg=-Wl,--disable-auto-image-base"]

      # If the gem is installed on a host with build tools installed, but is
      # run on one that isn't the missing libraries will cause the extension
      # to fail on start.
      flags += ["-C", "link-arg=-static-libgcc"]
    elsif darwin_target?
      # Ventura does not always have this flag enabled
      flags += ["-C", "link-arg=-Wl,-undefined,dynamic_lookup"]
    end

    flags
  end

  # We want to use the same linker that Ruby uses, so that the linker flags from
  # mkmf work properly.
  def linker_args
    cc_flag = Shellwords.split(makefile_config("CC"))
    linker = cc_flag.shift
    link_args = cc_flag.flat_map {|a| ["-C", "link-arg=#{a}"] }

    return mswin_link_args if linker == "cl"

    ["-C", "linker=#{linker}", *link_args]
  end

  def mswin_link_args
    args = []
    args += ["-l", makefile_config("LIBRUBYARG_SHARED").chomp(".lib")]
    args += split_flags("LIBS").flat_map {|lib| ["-l", lib.chomp(".lib")] }
    args += split_flags("LOCAL_LIBS").flat_map {|lib| ["-l", lib.chomp(".lib")] }
    args
  end

  def libruby_args(dest_dir)
    libs = makefile_config(ruby_static? ? "LIBRUBYARG_STATIC" : "LIBRUBYARG_SHARED")
    raw_libs = Shellwords.split(libs)
    raw_libs.flat_map {|l| ldflag_to_link_modifier(l) }
  end

  def ruby_static?
    return true if %w[1 true].include?(ENV["RUBY_STATIC"])

    makefile_config("ENABLE_SHARED") == "no"
  end

  def cargo_dylib_path(dest_path, crate_name)
    prefix = so_ext == "dll" ? "" : "lib"
    path_parts = [dest_path]
    path_parts << ENV["CARGO_BUILD_TARGET"] if ENV["CARGO_BUILD_TARGET"]
    path_parts += ["release", "#{prefix}#{crate_name}.#{so_ext}"]
    File.join(*path_parts)
  end

  def cargo_crate_name(cargo_dir, manifest_path, results)
    require "open3"
    Gem.load_yaml

    output, status =
      begin
        Open3.capture2e(cargo, "metadata", "--no-deps", "--format-version", "1", :chdir => cargo_dir)
      rescue => error
        raise Gem::InstallError, "cargo metadata failed #{error.message}"
      end

    unless status.success?
      if Gem.configuration.really_verbose
        puts output
      else
        results << output
      end

      exit_reason =
        if status.exited?
          ", exit code #{status.exitstatus}"
        elsif status.signaled?
          ", uncaught signal #{status.termsig}"
        end

      raise Gem::InstallError, "cargo metadata failed#{exit_reason}"
    end

    # cargo metadata output is specified as json, but with the
    # --format-version 1 option the output is compatible with YAML, so we can
    # avoid the json dependency
    metadata = Gem::SafeYAML.safe_load(output)
    package = metadata["packages"].find {|pkg| pkg["manifest_path"] == manifest_path }
    package["name"].tr("-", "_")
  end

  def rustc_dynamic_linker_flags(dest_dir, crate_name)
    split_flags("DLDFLAGS")
      .map {|arg| maybe_resolve_ldflag_variable(arg, dest_dir, crate_name) }
      .compact
      .flat_map {|arg| ldflag_to_link_modifier(arg) }
  end

  def rustc_lib_flags(dest_dir)
    split_flags("LIBS").flat_map {|arg| ldflag_to_link_modifier(arg) }
  end

  def split_flags(var)
    Shellwords.split(RbConfig::CONFIG.fetch(var, ""))
  end

  def ldflag_to_link_modifier(arg)
    LinkFlagConverter.convert(arg)
  end

  def msvc_target?
    makefile_config("target_os").include?("msvc")
  end

  def darwin_target?
    makefile_config("target_os").include?("darwin")
  end

  def mingw_target?
    makefile_config("target_os").include?("mingw")
  end

  def win_target?
    target_platform = RbConfig::CONFIG["target_os"]
    !!Gem::WIN_PATTERNS.find {|r| target_platform =~ r }
  end

  # Interpolate substitution vars in the arg (i.e. $(DEFFILE))
  def maybe_resolve_ldflag_variable(input_arg, dest_dir, crate_name)
    var_matches = input_arg.match(/\$\((\w+)\)/)

    return input_arg unless var_matches

    var_name = var_matches[1]

    return input_arg if var_name.nil? || var_name.chomp.empty?

    case var_name
    # On windows, it is assumed that mkmf has setup an exports file for the
    # extension, so we have to to create one ourselves.
    when "DEFFILE"
      write_deffile(dest_dir, crate_name)
    else
      RbConfig::CONFIG[var_name]
    end
  end

  def write_deffile(dest_dir, crate_name)
    deffile_path = File.join(dest_dir, "#{crate_name}-#{RbConfig::CONFIG["arch"]}.def")
    export_prefix = makefile_config("EXPORT_PREFIX") || ""

    File.open(deffile_path, "w") do |f|
      f.puts "EXPORTS"
      f.puts "#{export_prefix.strip}Init_#{crate_name}"
    end

    deffile_path
  end

  # We have to basically reimplement RbConfig::CONFIG['SOEXT'] here to support
  # Ruby < 2.5
  #
  # @see https://github.com/ruby/ruby/blob/c87c027f18c005460746a74c07cd80ee355b16e4/configure.ac#L3185
  def so_ext
    return RbConfig::CONFIG["SOEXT"] if RbConfig::CONFIG.key?("SOEXT")

    if win_target?
      "dll"
    elsif darwin_target?
      "dylib"
    else
      "so"
    end
  end

  # Corresponds to $(LIBPATH) in mkmf
  def mkmf_libpath
    ["-L", "native=#{makefile_config("libdir")}"]
  end

  def makefile_config(var_name)
    val = RbConfig::MAKEFILE_CONFIG[var_name]

    return unless val

    RbConfig.expand(val.dup)
  end

  # Error raised when no cdylib artifact was created
  class DylibNotFoundError < StandardError
    def initialize(dir)
      files = Dir.glob(File.join(dir, "**", "*")).map {|f| "- #{f}" }.join "\n"

      super <<~MSG
        Dynamic library not found for Rust extension (in #{dir})

        Make sure you set "crate-type" in Cargo.toml to "cdylib"

        Found files:
        #{files}
      MSG
    end
  end
end
