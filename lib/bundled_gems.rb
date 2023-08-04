module Gem::BUNDLED_GEMS
  SINCE = {
    "rexml" => "3.0.0",
    "rss" => "3.0.0",
    "webrick" => "3.0.0",
    "matrix" => "3.1.0",
    "net-ftp" => "3.1.0",
    "net-imap" => "3.1.0",
    "net-pop" => "3.1.0",
    "net-smtp" => "3.1.0",
    "abbrev" => "3.4.0",
    "observer" => "3.4.0",
    "getoptlong" => "3.4.0",
    "resolv-replace" => "3.4.0",
    "rinda" => "3.4.0",
    "nkf" => "3.4.0",
    "syslog" => "3.4.0",
    "drb" => "3.4.0",
    "mutex_m" => "3.4.0",
    "csv" => "3.4.0",
    "base64" => "3.4.0"
  }.freeze

  EXACT = {
    "abbrev"=>true,
    "base64"=>true,
    "csv"=>true,
    "drb"=>true,
    "getoptlong"=>true,
    "mutex_m"=>true,
    "nkf"=>true, "kconv"=>"nkf",
    "observer"=>true,
    "resolv-replace"=>true,
    "rinda"=>true,
    "syslog"=>true,
  }.freeze

  PREFIXED = {
    "csv" => true,
    "drb" => true,
    "rinda" => true,
    "syslog" => true,
  }.freeze

  WARNED = {}                   # unfrozen

  conf = ::RbConfig::CONFIG
  LIBDIR = (conf["rubylibdir"] + "/").freeze
  ARCHDIR = (conf["rubyarchdir"] + "/").freeze
  DLEXT = /\.#{Regexp.union([conf["DLEXT"], "so"].uniq)}\z/

  def self.find_gem(path)
    if !path
      return
    elsif path.start_with?(ARCHDIR)
      n = path.delete_prefix(ARCHDIR).sub(DLEXT, "")
    elsif path.start_with?(LIBDIR)
      n = path.delete_prefix(LIBDIR).chomp(".rb")
    else
      return
    end
    EXACT[n] or PREFIXED[n[%r[\A[^/]+(?=/)]]]
  end

  def self.warning?(name)
    _t, path = $:.resolve_feature_path(name)
    return unless gem = find_gem(path)
    caller, = caller_locations(3, 1)
    return if find_gem(caller&.absolute_path)
    return if WARNED[name]
    WARNED[name] = true
    if gem == true
      gem = name
    elsif gem
      return if WARNED[gem]
      WARNED[gem] = true
      "#{name} is found in #{gem}"
    else
      return
    end + " which is not part of the default gems since Ruby #{SINCE[gem]}"
  end

  bundled_gems = self

  define_method(:find_unresolved_default_spec) do |name|
    if msg = bundled_gems.warning?(name)
      warn msg, uplevel: 1
    end
    super(name)
  end

  freeze
end

Gem.singleton_class.prepend Gem::BUNDLED_GEMS
