require 'rubygems'
require 'gauntlet'

##
# GemGauntlet validates all current gems. Currently these packages are
# borked:
#
# Asami-0.04           : No such file or directory - bin/Asami.rb
# ObjectGraph-1.0.1    : No such file or directory - bin/objectgraph
# evil-ruby-0.1.0      : authors must be Array of Strings
# fresh_cookies-1.0.0  : authors must be Array of Strings
# plugems_deploy-0.2.0 : authors must be Array of Strings
# pmsrb-0.2.0          : authors must be Array of Strings
# pqa-1.6              : authors must be Array of Strings
# rant-0.5.7           : authors must be Array of Strings
# rvsh-0.4.5           : No such file or directory - bin/rvsh
# xen-0.1.2.1          : authors must be Array of Strings

class GemGauntlet < Gauntlet
  def run(name)
    warn name

    spec = begin
             Gem::Specification.load 'gemspec'
           rescue SyntaxError
             Gem::Specification.from_yaml File.read('gemspec')
           end
    spec.validate

    self.data[name] = false
    self.dirty = true
  rescue SystemCallError, Gem::InvalidSpecificationException => e
    self.data[name] = e.message
    self.dirty = true
  end

  def should_skip?(name)
    self.data[name] == false
  end

  def report
    self.data.sort.reject { |k,v| !v }.each do |k,v|
      puts "%-21s: %s" % [k, v]
    end
  end
end

gauntlet = GemGauntlet.new
gauntlet.run_the_gauntlet ARGV.shift
gauntlet.report
