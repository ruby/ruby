# -*- frozen-string-literal: true -*-

module Gem::BUNDLED_GEMS # :nodoc:
  SINCE = {
    "matrix" => "3.1.0",
    "net-ftp" => "3.1.0",
    "net-imap" => "3.1.0",
    "net-pop" => "3.1.0",
    "net-smtp" => "3.1.0",
    "prime" => "3.1.0",
    "racc" => "3.3.0",
    "abbrev" => "3.4.0",
    "base64" => "3.4.0",
    "bigdecimal" => "3.4.0",
    "csv" => "3.4.0",
    "drb" => "3.4.0",
    "getoptlong" => "3.4.0",
    "mutex_m" => "3.4.0",
    "nkf" => "3.4.0",
    "observer" => "3.4.0",
    "resolv-replace" => "3.4.0",
    "rinda" => "3.4.0",
    "syslog" => "3.4.0",
    "ostruct" => "3.5.0",
    "pstore" => "3.5.0",
    "rdoc" => "3.5.0",
    "win32ole" => "3.5.0",
    "fiddle" => "3.5.0",
    "logger" => "3.5.0",
    "benchmark" => "3.5.0",
    "irb" => "3.5.0",
    "reline" => "3.5.0",
    # "readline" => "3.5.0", # This is wrapper for reline. We don't warn for this.
  }.freeze

  SINCE_FAST_PATH = SINCE.transform_keys { |g| g.sub(/\A.*\-/, "") }.freeze

  EXACT = {
    "kconv" => "nkf",
  }.freeze

  PREFIXED = {
    "bigdecimal" => true,
    "csv" => true,
    "drb" => true,
    "rinda" => true,
    "syslog" => true,
    "fiddle" => true,
  }.freeze

  WARNED = {}                   # unfrozen

  conf = ::RbConfig::CONFIG
  if ENV["TEST_BUNDLED_GEMS_FAKE_RBCONFIG"]
    LIBDIR = (File.expand_path(File.join(__dir__, "..", "lib")) + "/").freeze
    rubyarchdir = $LOAD_PATH.find{|path| path.include?(".ext/common") }
    ARCHDIR = (File.expand_path(rubyarchdir) + "/").freeze
  else
    LIBDIR = (conf["rubylibdir"] + "/").freeze
    ARCHDIR = (conf["rubyarchdir"] + "/").freeze
  end
  dlext = [conf["DLEXT"], "so"].uniq
  DLEXT = /\.#{Regexp.union(dlext)}\z/
  LIBEXT = /\.#{Regexp.union("rb", *dlext)}\z/

  def self.replace_require(specs)
    return if [::Kernel.singleton_class, ::Kernel].any? {|klass| klass.respond_to?(:no_warning_require) }

    spec_names = specs.to_a.each_with_object({}) {|spec, h| h[spec.name] = true }

    [::Kernel.singleton_class, ::Kernel].each do |kernel_class|
      kernel_class.send(:alias_method, :no_warning_require, :require)
      kernel_class.send(:define_method, :require) do |name|
        if message = ::Gem::BUNDLED_GEMS.warning?(name, specs: spec_names)
          uplevel = ::Gem::BUNDLED_GEMS.uplevel
          if uplevel > 0
            Kernel.warn message, uplevel: uplevel
          else
            Kernel.warn message
          end
        end
        kernel_class.send(:no_warning_require, name)
      end
      if kernel_class == ::Kernel
        kernel_class.send(:private, :require)
      else
        kernel_class.send(:public, :require)
      end
    end
  end

  def self.uplevel
    frame_count = 0
    require_labels = ["replace_require", "require"]
    uplevel = 0
    require_found = false
    Thread.each_caller_location do |cl|
      frame_count += 1

      if require_found
        unless require_labels.include?(cl.base_label)
          return uplevel
        end
      else
        if require_labels.include?(cl.base_label)
          require_found = true
        end
      end
      uplevel += 1
      # Don't show script name when bundle exec and call ruby script directly.
      if cl.path.end_with?("bundle")
        frame_count = 0
        break
      end
    end
    require_found ? 1 : frame_count - 1
  end

  def self.find_gem(path)
    if !path
      return
    elsif path.start_with?(ARCHDIR)
      n = path.delete_prefix(ARCHDIR).sub(DLEXT, "").chomp(".rb")
    elsif path.start_with?(LIBDIR)
      n = path.delete_prefix(LIBDIR).chomp(".rb")
    else
      return
    end
    (EXACT[n] || !!SINCE[n]) or PREFIXED[n = n[%r[\A[^/]+(?=/)]]] && n
  end

  def self.warning?(name, specs: nil)
    # name can be a feature name or a file path with String or Pathname
    feature = File.path(name)

    # irb already has reline as a dependency on gemspec, so we don't want to warn about it.
    # We should update this with a more general solution when we have another case.
    # ex: Gem.loaded_specs[called_gem].dependencies.any? {|d| d.name == feature }
    return false if feature.start_with?("reline") && caller_locations(2, 1)[0].to_s.include?("irb")

    # The actual checks needed to properly identify the gem being required
    # are costly (see [Bug #20641]), so we first do a much cheaper check
    # to exclude the vast majority of candidates.
    if feature.include?("/")
      # bootsnap expands `require "csv"` to `require "#{LIBDIR}/csv.rb"`,
      # and `require "syslog"` to `require "#{ARCHDIR}/syslog.so"`.
      name = feature.delete_prefix(ARCHDIR).delete_prefix(LIBDIR).sub(LIBEXT, "")
      segments = name.split("/")
      name = segments.first
      if !SINCE[name]
        name = segments[0..1].join("-")
        return unless SINCE[name]
      end
    else
      name = feature.sub(LIBEXT, "")
      return unless SINCE_FAST_PATH[name]
    end

    return if specs.include?(name)
    _t, path = $:.resolve_feature_path(feature)
    if gem = find_gem(path)
      return if specs.include?(gem)
    elsif SINCE[name] && !path
      gem = true
    else
      return
    end

    return if WARNED[name]
    WARNED[name] = true
    if gem == true
      gem = name
      "#{feature} was loaded from the standard library, but"
    elsif gem
      "#{feature} is found in #{gem}, which"
    else
      return
    end + build_message(gem)
  end

  def self.build_message(gem)
    msg = " #{RUBY_VERSION < SINCE[gem] ? "will no longer be" : "is not"} part of the default gems starting from Ruby #{SINCE[gem]}."

    if defined?(Bundler)
      msg += "\nYou can add #{gem} to your Gemfile or gemspec to silence this warning."

      # We detect the gem name from caller_locations. First we walk until we find `require`
      # then take the first frame that's not from `require`.
      #
      # Additionally, we need to skip Bootsnap and Zeitwerk if present, these
      # gems decorate Kernel#require, so they are not really the ones issuing
      # the require call users should be warned about. Those are upwards.
      frames_to_skip = 3
      location = nil
      require_found = false
      Thread.each_caller_location do |cl|
        if frames_to_skip >= 1
          frames_to_skip -= 1
          next
        end

        if require_found
          if cl.base_label != "require"
            location = cl.path
            break
          end
        else
          if cl.base_label == "require"
            require_found = true
          end
        end
      end

      if location && File.file?(location) && !location.start_with?(Gem::BUNDLED_GEMS::LIBDIR)
        caller_gem = nil
        Gem.path.each do |path|
          if location =~ %r{#{path}/gems/([\w\-\.]+)}
            caller_gem = $1
            break
          end
        end
        if caller_gem
          msg += "\nAlso please contact the author of #{caller_gem} to request adding #{gem} into its gemspec."
        end
      end
    else
      msg += " Install #{gem} from RubyGems."
    end

    msg
  end

  freeze
end

# for RubyGems without Bundler environment.
# If loading library is not part of the default gems and the bundled gems, warn it.
class LoadError
  def message # :nodoc:
    return super unless path

    name = path.tr("/", "-")
    if !defined?(Bundler) && Gem::BUNDLED_GEMS::SINCE[name] && !Gem::BUNDLED_GEMS::WARNED[name]
      warn name + Gem::BUNDLED_GEMS.build_message(name), uplevel: Gem::BUNDLED_GEMS.uplevel
    end
    super
  end
end
