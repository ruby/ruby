#!/usr/bin/env ruby

require "rbconfig"

c = Config::CONFIG
ruby = File.join(c['bindir'], c['ruby_install_name'])

module RSS
	AVAILABLE_PARSERS = [ARGV.shift]
end

def load_test_file(name)
	puts "Loading #{name} ..."
	require name
end

load_test_file(ARGV.shift)
