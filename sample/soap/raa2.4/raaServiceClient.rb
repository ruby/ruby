#!/usr/bin/env ruby
require 'raaDriver.rb'

endpoint_url = ARGV.shift
obj = RaaServicePortType.new(endpoint_url)

# Uncomment the below line to see SOAP wiredumps.
# obj.wiredump_dev = STDERR

# SYNOPSIS
#   gem(name)
#
# ARGS
#   name		 - {http://www.w3.org/2001/XMLSchema}string
#
# RETURNS
#   return		Gem - {http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/}Gem
#
# RAISES
#   (undefined)
#
name = nil
puts obj.gem(name)

# SYNOPSIS
#   dependents(name, version)
#
# ARGS
#   name		 - {http://www.w3.org/2001/XMLSchema}string
#   version		 - {http://www.w3.org/2001/XMLSchema}string
#
# RETURNS
#   return		ProjectDependencyArray - {http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/}ProjectDependencyArray
#
# RAISES
#   (undefined)
#
name = version = nil
puts obj.dependents(name, version)

# SYNOPSIS
#   names
#
# ARGS
#   N/A
#
# RETURNS
#   return		StringArray - {http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/}StringArray
#
# RAISES
#   (undefined)
#

puts obj.names

# SYNOPSIS
#   size
#
# ARGS
#   N/A
#
# RETURNS
#   return		 - {http://www.w3.org/2001/XMLSchema}int
#
# RAISES
#   (undefined)
#

puts obj.size

# SYNOPSIS
#   list_by_category(major, minor)
#
# ARGS
#   major		 - {http://www.w3.org/2001/XMLSchema}string
#   minor		 - {http://www.w3.org/2001/XMLSchema}string
#
# RETURNS
#   return		StringArray - {http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/}StringArray
#
# RAISES
#   (undefined)
#
major = minor = nil
puts obj.list_by_category(major, minor)

# SYNOPSIS
#   tree_by_category
#
# ARGS
#   N/A
#
# RETURNS
#   return		Map - {http://xml.apache.org/xml-soap}Map
#
# RAISES
#   (undefined)
#

puts obj.tree_by_category

# SYNOPSIS
#   list_recent_updated(idx)
#
# ARGS
#   idx		 - {http://www.w3.org/2001/XMLSchema}int
#
# RETURNS
#   return		StringArray - {http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/}StringArray
#
# RAISES
#   (undefined)
#
idx = nil
puts obj.list_recent_updated(idx)

# SYNOPSIS
#   list_recent_created(idx)
#
# ARGS
#   idx		 - {http://www.w3.org/2001/XMLSchema}int
#
# RETURNS
#   return		StringArray - {http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/}StringArray
#
# RAISES
#   (undefined)
#
idx = nil
puts obj.list_recent_created(idx)

# SYNOPSIS
#   list_updated_since(date, idx)
#
# ARGS
#   date		 - {http://www.w3.org/2001/XMLSchema}dateTime
#   idx		 - {http://www.w3.org/2001/XMLSchema}int
#
# RETURNS
#   return		StringArray - {http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/}StringArray
#
# RAISES
#   (undefined)
#
date = idx = nil
puts obj.list_updated_since(date, idx)

# SYNOPSIS
#   list_created_since(date, idx)
#
# ARGS
#   date		 - {http://www.w3.org/2001/XMLSchema}dateTime
#   idx		 - {http://www.w3.org/2001/XMLSchema}int
#
# RETURNS
#   return		StringArray - {http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/}StringArray
#
# RAISES
#   (undefined)
#
date = idx = nil
puts obj.list_created_since(date, idx)

# SYNOPSIS
#   list_by_owner(owner_id)
#
# ARGS
#   owner_id		 - {http://www.w3.org/2001/XMLSchema}int
#
# RETURNS
#   return		StringArray - {http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/}StringArray
#
# RAISES
#   (undefined)
#
owner_id = nil
puts obj.list_by_owner(owner_id)

# SYNOPSIS
#   search_name(substring, idx)
#
# ARGS
#   substring		 - {http://www.w3.org/2001/XMLSchema}string
#   idx		 - {http://www.w3.org/2001/XMLSchema}int
#
# RETURNS
#   return		StringArray - {http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/}StringArray
#
# RAISES
#   (undefined)
#
substring = idx = nil
puts obj.search_name(substring, idx)

# SYNOPSIS
#   search_short_description(substring, idx)
#
# ARGS
#   substring		 - {http://www.w3.org/2001/XMLSchema}string
#   idx		 - {http://www.w3.org/2001/XMLSchema}int
#
# RETURNS
#   return		StringArray - {http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/}StringArray
#
# RAISES
#   (undefined)
#
substring = idx = nil
puts obj.search_short_description(substring, idx)

# SYNOPSIS
#   search_owner(substring, idx)
#
# ARGS
#   substring		 - {http://www.w3.org/2001/XMLSchema}string
#   idx		 - {http://www.w3.org/2001/XMLSchema}int
#
# RETURNS
#   return		StringArray - {http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/}StringArray
#
# RAISES
#   (undefined)
#
substring = idx = nil
puts obj.search_owner(substring, idx)

# SYNOPSIS
#   search_version(substring, idx)
#
# ARGS
#   substring		 - {http://www.w3.org/2001/XMLSchema}string
#   idx		 - {http://www.w3.org/2001/XMLSchema}int
#
# RETURNS
#   return		StringArray - {http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/}StringArray
#
# RAISES
#   (undefined)
#
substring = idx = nil
puts obj.search_version(substring, idx)

# SYNOPSIS
#   search_status(substring, idx)
#
# ARGS
#   substring		 - {http://www.w3.org/2001/XMLSchema}string
#   idx		 - {http://www.w3.org/2001/XMLSchema}int
#
# RETURNS
#   return		StringArray - {http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/}StringArray
#
# RAISES
#   (undefined)
#
substring = idx = nil
puts obj.search_status(substring, idx)

# SYNOPSIS
#   search_description(substring, idx)
#
# ARGS
#   substring		 - {http://www.w3.org/2001/XMLSchema}string
#   idx		 - {http://www.w3.org/2001/XMLSchema}int
#
# RETURNS
#   return		StringArray - {http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/}StringArray
#
# RAISES
#   (undefined)
#
substring = idx = nil
puts obj.search_description(substring, idx)

# SYNOPSIS
#   search(substring)
#
# ARGS
#   substring		 - {http://www.w3.org/2001/XMLSchema}string
#
# RETURNS
#   return		Map - {http://xml.apache.org/xml-soap}Map
#
# RAISES
#   (undefined)
#
substring = nil
puts obj.search(substring)

# SYNOPSIS
#   owner(owner_id)
#
# ARGS
#   owner_id		 - {http://www.w3.org/2001/XMLSchema}int
#
# RETURNS
#   return		Owner - {http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/}Owner
#
# RAISES
#   (undefined)
#
owner_id = nil
puts obj.owner(owner_id)

# SYNOPSIS
#   list_owner(idx)
#
# ARGS
#   idx		 - {http://www.w3.org/2001/XMLSchema}int
#
# RETURNS
#   return		OwnerArray - {http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/}OwnerArray
#
# RAISES
#   (undefined)
#
idx = nil
puts obj.list_owner(idx)

# SYNOPSIS
#   update(name, pass, gem)
#
# ARGS
#   name		 - {http://www.w3.org/2001/XMLSchema}string
#   pass		 - {http://www.w3.org/2001/XMLSchema}string
#   gem		Gem - {http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/}Gem
#
# RETURNS
#   return		Gem - {http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/}Gem
#
# RAISES
#   (undefined)
#
name = pass = gem = nil
puts obj.update(name, pass, gem)

# SYNOPSIS
#   update_pass(name, oldpass, newpass)
#
# ARGS
#   name		 - {http://www.w3.org/2001/XMLSchema}string
#   oldpass		 - {http://www.w3.org/2001/XMLSchema}string
#   newpass		 - {http://www.w3.org/2001/XMLSchema}string
#
# RETURNS
#   N/A
#
# RAISES
#   (undefined)
#
name = oldpass = newpass = nil
puts obj.update_pass(name, oldpass, newpass)


