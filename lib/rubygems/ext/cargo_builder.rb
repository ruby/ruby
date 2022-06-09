# frozen_string_literal: true

# This class is used by rubygems to build Rust extensions. It is a thin-wrapper
# over the `cargo rustc` command which takes care of building Rust code in a way
# that Ruby can use.
class Gem::Ext::CargoBuilder < Gem::Ext::Builder
  attr_reader :spec

  def initialize(spec)
    @spec = spec
  end

  def build(_extension, dest_path, results, args = [], lib_dir = nil, cargo_dir = Dir.pwd)
    require "rubygems/command"
    require "fileutils"
    require "shellwords"

    build_crate(dest_path, results, args, cargo_dir)
    ext_path = rename_cdylib_for_ruby_compatibility(dest_path)
    finalize_directory(ext_path, dest_path, lib_dir, cargo_dir)
    results
  end

  private

  def build_crate(dest_path, results, args, cargo_dir)
    manifest = File.join(cargo_dir, "Cargo.toml")

    given_ruby_static = ENV["RUBY_STATIC"]

    ENV["RUBY_STATIC"] = "true" if ruby_static? && !given_ruby_static

    cargo = ENV.fetch("CARGO", "cargo")

    cmd = []
    cmd += [cargo, "rustc"]
    cmd += ["--target-dir", dest_path]
    cmd += ["--manifest-path", manifest]
    cmd += ["--lib", "--release", "--locked"]
    cmd += ["--"]
    cmd += [*cargo_rustc_args(dest_path)]
    cmd += Gem::Command.build_args
    cmd += args

    self.class.run cmd, results, self.class.class_name, cargo_dir
    results
  ensure
    ENV["RUBY_STATIC"] = given_ruby_static
  end

  def cargo_rustc_args(dest_dir)
    [
      *linker_args,
      *mkmf_libpath,
      *rustc_dynamic_linker_flags(dest_dir),
      *rustc_lib_flags(dest_dir),
      *platform_specific_rustc_args(dest_dir),
      *debug_flags,
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
    end

    flags
  end

  # We want to use the same linker that Ruby uses, so that the linker flags from
  # mkmf work properly.
  def linker_args
    # Have to handle CC="cl /nologo" on mswin
    cc_flag = Shellwords.split(makefile_config("CC"))
    linker = cc_flag.shift
    link_args = cc_flag.flat_map {|a| ["-C", "link-arg=#{a}"] }

    ["-C", "linker=#{linker}", *link_args]
  end

  def libruby_args(dest_dir)
    libs = makefile_config(ruby_static? ? "LIBRUBYARG_STATIC" : "LIBRUBYARG_SHARED")
    raw_libs = Shellwords.split(libs)
    raw_libs.flat_map {|l| ldflag_to_link_modifier(l, dest_dir) }
  end

  def ruby_static?
    return true if %w[1 true].include?(ENV["RUBY_STATIC"])

    makefile_config("ENABLE_SHARED") == "no"
  end

  # Ruby expects the dylib to follow a file name convention for loading
  def rename_cdylib_for_ruby_compatibility(dest_path)
    dylib_path = validate_cargo_build!(dest_path)
    dlext_name = "#{spec.name}.#{makefile_config("DLEXT")}"
    new_name = dylib_path.gsub(File.basename(dylib_path), dlext_name)
    FileUtils.cp(dylib_path, new_name)
    new_name
  end

  def validate_cargo_build!(dir)
    prefix = so_ext == "dll" ? "" : "lib"
    dylib_path = File.join(dir, "release", "#{prefix}#{cargo_crate_name}.#{so_ext}")

    raise DylibNotFoundError, dir unless File.exist?(dylib_path)

    dylib_path
  end

  def cargo_crate_name
    spec.metadata.fetch('cargo_crate_name', spec.name).tr('-', '_')
  end

  def rustc_dynamic_linker_flags(dest_dir)
    split_flags("DLDFLAGS")
      .map {|arg| maybe_resolve_ldflag_variable(arg, dest_dir) }
      .compact
      .flat_map {|arg| ldflag_to_link_modifier(arg, dest_dir) }
  end

  def rustc_lib_flags(dest_dir)
    split_flags("LIBS").flat_map {|arg| ldflag_to_link_modifier(arg, dest_dir) }
  end

  def split_flags(var)
    Shellwords.split(RbConfig::CONFIG.fetch(var, ""))
  end

  def ldflag_to_link_modifier(arg, dest_dir)
    flag = arg[0..1]
    val = arg[2..-1]

    case flag
    when "-L" then ["-L", "native=#{val}"]
    when "-l" then ["-l", val.to_s]
    when "-F" then ["-l", "framework=#{val}"]
    else ["-C", "link_arg=#{arg}"]
    end
  end

  def link_flag(link_name)
    # These are provided by the CRT with MSVC
    # @see https://github.com/rust-lang/pkg-config-rs/blob/49a4ac189aafa365167c72e8e503565a7c2697c2/src/lib.rs#L622
    return [] if msvc_target? && ["m", "c", "pthread"].include?(link_name)

    if link_name.include?("ruby")
      # Specify the lib kind and give it the name "ruby" for linking
      kind = ruby_static? ? "static" : "dylib"

      ["-l", "#{kind}=ruby:#{link_name}"]
    else
      ["-l", link_name]
    end
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

  # Intepolate substition vars in the arg (i.e. $(DEFFILE))
  def maybe_resolve_ldflag_variable(input_arg, dest_dir)
    str = input_arg.gsub(/\$\((\w+)\)/) do |var_name|
      case var_name
      # On windows, it is assumed that mkmf has setup an exports file for the
      # extension, so we have to to create one ourselves.
      when "DEFFILE"
        write_deffile(dest_dir)
      else
        RbConfig::CONFIG[var_name]
      end
    end.strip

    str == "" ? nil : str
  end

  def write_deffile(dest_dir)
    deffile_path = File.join(dest_dir, "#{spec.name}-#{RbConfig::CONFIG["arch"]}.def")
    export_prefix = makefile_config("EXPORT_PREFIX") || ""

    File.open(deffile_path, "w") do |f|
      f.puts "EXPORTS"
      f.puts "#{export_prefix.strip}Init_#{spec.name}"
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

  # Good balance between binary size and debugability
  def debug_flags
    ["-C", "debuginfo=1"]
  end

  # Copied from ExtConfBuilder
  def finalize_directory(ext_path, dest_path, lib_dir, extension_dir)
    require "fileutils"
    require "tempfile"

    begin
      tmp_dest = Dir.mktmpdir(".gem.", extension_dir)

      # Some versions of `mktmpdir` return absolute paths, which will break make
      # if the paths contain spaces. However, on Ruby 1.9.x on Windows, relative
      # paths cause all C extension builds to fail.
      #
      # As such, we convert to a relative path unless we are using Ruby 1.9.x on
      # Windows. This means that when using Ruby 1.9.x on Windows, paths with
      # spaces do not work.
      #
      # Details: https://github.com/rubygems/rubygems/issues/977#issuecomment-171544940
      tmp_dest_relative = get_relative_path(tmp_dest.clone, extension_dir)

      if tmp_dest_relative
        full_tmp_dest = File.join(extension_dir, tmp_dest_relative)

        # TODO: remove in RubyGems 3
        if Gem.install_extension_in_lib && lib_dir
          FileUtils.mkdir_p lib_dir
          FileUtils.cp_r ext_path, lib_dir, remove_destination: true
        end

        FileUtils::Entry_.new(full_tmp_dest).traverse do |ent|
          destent = ent.class.new(dest_path, ent.rel)
          destent.exist? || FileUtils.mv(ent.path, destent.path)
        end
      end
    ensure
      FileUtils.rm_rf tmp_dest if tmp_dest
    end
  end

  def get_relative_path(path, base)
    path[0..base.length - 1] = "." if path.start_with?(base)
    path
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
