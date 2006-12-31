require 'rbconfig'
$:.unshift File.join('.ext', Config::CONFIG['arch'])
$:.unshift '.ext'
load ARGV[0]
