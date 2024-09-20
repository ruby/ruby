module Path
  module_function

  def clean(path)
    path = "#{path}/".gsub(/(\A|\/)(?:\.\/)+/, '\1').tr_s('/', '/')
    nil while path.sub!(/[^\/]+\/\.\.\//, '')
    path
  end

  def relative(path, base)
    path = clean(path)
    base = clean(base)
    path, base = [path, base].map{|s|s.split("/")}
    until path.empty? or base.empty? or path[0] != base[0]
      path.shift
      base.shift
    end
    path, base = [path, base].map{|s|s.join("/")}
    if base.empty?
      path
    elsif base.start_with?("../") or File.absolute_path?(base)
      File.expand_path(path)
    else
      base.gsub!(/[^\/]+/, '..')
      File.join(base, path)
    end
  end

  def clean_link(src, dest)
    begin
      link = File.readlink(dest)
    rescue
    else
      return if link == src
      File.unlink(dest)
    end
    yield src, dest
  end

  # Extensions to FileUtils

  module Mswin
    def ln_safe(src, dest, real_src, *opt)
      cmd = ["mklink", dest.tr("/", "\\"), src.tr("/", "\\")]
      cmd[1, 0] = opt
      return if system("cmd", "/c", *cmd)
      # TODO: use RUNAS or something
      puts cmd.join(" ")
    end

    def ln_dir_safe(src, dest, real_src)
      ln_safe(src, dest, "/d")
    end
  end

  module HardlinkExcutable
    def ln_exe(relative_src, dest, src)
      ln(src, dest, force: true)
    end
  end

  def ln_safe(src, dest, real_src)
    ln_sf(src, dest)
  rescue Errno::ENOENT
    # Windows disallows to create broken symboic links, probably because
    # it is a kind of reparse points.
    raise if File.exist?(real_src)
  end

  alias ln_dir_safe ln_safe
  alias ln_exe ln_safe

  def ln_relative(src, dest, executable = false)
    return if File.identical?(src, dest)
    parent = File.dirname(dest)
    File.directory?(parent) or mkdir_p(parent)
    if executable
      return (ln_exe(relative(src, parent), dest, src) if File.exist?(src))
    end
    clean_link(relative(src, parent), dest) {|s, d| ln_safe(s, d, src)}
  end

  def ln_dir_relative(src, dest)
    return if File.identical?(src, dest)
    parent = File.dirname(dest)
    File.directory?(parent) or mkdir_p(parent)
    clean_link(relative(src, parent), dest) {|s, d| ln_dir_safe(s, d, src)}
  end

  case (CROSS_COMPILING || RUBY_PLATFORM)
  when /linux|darwin|solaris/
    prepend HardlinkExcutable
    extend HardlinkExcutable
  when /mingw|mswin/
    unless File.respond_to?(:symlink)
      prepend Mswin
      extend Mswin
    end
  else
  end
end
