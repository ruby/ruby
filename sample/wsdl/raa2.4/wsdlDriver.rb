#!/usr/bin/env ruby

# You can generate raa.rb required here with the command;
# wsdl2ruby.rb --wsdl http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/ --classdef
require 'raa'
require 'soap/wsdlDriver'
require 'pp'

RAA_WSDL = 'http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/'

raa = SOAP::WSDLDriverFactory.new(RAA_WSDL).create_driver
raa.generate_explicit_type = true
# raa.wiredump_dev = STDERR

def sec(msg)
  puts
  puts "--------"
  puts "-- " + msg
  puts
end

def subsec(msg)
  puts "-- " + msg
end

sec("retrieve a gem (RAA Information) which has specified name")
name = 'soap4r'
pp raa.gem(name)

sec("retrieve dependents of the project")
name = 'http-access2'; version = nil
pp raa.dependents(name, version)

sec("number of registered gems")
puts raa.size

sec("retrieve all registered gem names")
p raa.names

sec("retrieve gems of specified category")
major = 'Library'; minor = 'XML'
p raa.list_by_category(major, minor)

sec("retrieve category tree")
pp raa.tree_by_category

sec("retrieve gems which is updated recently")
idx = 0
p raa.list_recent_updated(idx)
subsec("next 10 gems")
idx += 1
p raa.list_recent_updated(idx)
subsec("next 10 gems")
idx += 1
p raa.list_recent_updated(idx)

sec("retrieve gems which is created recently")
p raa.list_recent_created(idx)

sec("retrieve gems which is updated in 7 days")
date = Time.now - 7 * 24 * 60 * 60; idx = 0
p raa.list_updated_since(date, idx)

sec("retrieve gems which is created in 7 days")
p raa.list_created_since(date, idx)

sec("retrieve gems of specified owner")
owner_id = 8    # NaHi
p raa.list_by_owner(owner_id)

sec("search gems with keyword")
substring = 'soap'
pp raa.search(substring)

# There are several search interface to search a field explicitly.
# puts raa.search_name(substring, idx)
# puts raa.search_short_description(substring, idx)
# puts raa.search_owner(substring, idx)
# puts raa.search_version(substring, idx)
# puts raa.search_status(substring, idx)
# puts raa.search_description(substring, idx)

sec("retrieve owner info")
owner_id = 8
pp raa.owner(owner_id)

sec("retrieve owners")
idx = 0
p raa.list_owner(idx)

sec("update 'sampleproject'")
name = 'sampleproject'
pass = 'sampleproject'
gem = raa.gem(name)
p gem.project.version
gem.project.version.succ!
gem.updated = Time.now
raa.update(name, pass, gem)
p raa.gem(name).project.version

sec("update pass phrase")
raa.update_pass(name, 'sampleproject', 'foo')
subsec("update check")
gem = raa.gem(name)
gem.project.description = 'Current pass phrase is "foo"'
gem.updated = Time.now
raa.update(name, 'foo', gem)
#
subsec("recover pass phrase")
raa.update_pass(name, 'foo', 'sampleproject')
subsec("update check")
gem = raa.gem(name)
gem.project.description = 'Current pass phrase is "sampleproject"'
gem.updated = Time.now
raa.update(name, 'sampleproject', gem)

sec("done")
