#
# tk/package.rb : package command
#
require 'tk'

module TkPackage
  include TkCore
  extend TkPackage

  TkCommandNames = ['package'.freeze].freeze

  def add_path(path)
    Tk::AUTO_PATH.value = Tk::AUTO_PATH.to_a << path
  end

  def forget(package)
    tk_call('package', 'forget', package)
    nil
  end

  def names
    tk_split_simplelist(tk_call('package', 'names'))
  end

  def provide(package, version=nil)
    if version
      tk_call('package', 'provide', package, version)
      nil
    else
      tk_call('package', 'provide', package)
    end
  end

  def present(package, version=None)
    tk_call('package', 'present', package, version)
  end

  def present_exact(package, version)
    tk_call('package', 'present', '-exact', package, version)
  end

  def require(package, version=None)
    tk_call('package', 'require', package, version)
  end

  def require_exact(package, version)
    tk_call('package', 'require', '-exact', package, version)
  end

  def versions(package)
    tk_split_simplelist(tk_call('package', 'versions', package))
  end

  def vcompare(version1, version2)
    number(tk_call('package', 'vcompare', version1, version2))
  end

  def vsatisfies(version1, version2)
    bool(tk_call('package', 'vsatisfies', version1, version2))
  end
end
