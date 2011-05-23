#
# YAML::Store
#
require 'yaml'
require 'pstore'

# YAML::Store provides the same functionality as PStore, except it uses YAML
# to dump objects instead of Marshal.
#
# == Example
#
#   require 'yaml/store'
#
#   Person = Struct.new :first_name, :last_name
#
#   people = [Person.new("Bob", "Smith"), Person.new("Mary", "Johnson")]
#
#   store = YAML::Store.new "test.store"
#
#   store.transaction do
#     store["people"] = people
#     store["greeting"] = { "hello" => "world" }
#   end
#
# After running the above code, the contents of "test.store" will be:
#
#   ---
#   people:
#   - !ruby/struct:Person
#     first_name: Bob
#     last_name: Smith
#   - !ruby/struct:Person
#     first_name: Mary
#     last_name: Johnson
#   greeting:
#     hello: world

class YAML::Store < PStore

  # :call-seq:
  #   initialize( file_name, yaml_opts = {} )
  #
  # Creates a new YAML::Store object, which will store data in +file_name+.
  # If the file does not already exist, it will be created.
  #
  #
  # Options passed in through +yaml_opts+ will be used when converting the
  # store to YAML via Hash#to_yaml().
  def initialize( *o )
    @opt = {}
    if String === o.first
      super(o.shift)
    end
    if o.last.is_a? Hash
      @opt.update(o.pop)
    end
  end

  # :stopdoc:

  def dump(table)
    @table.to_yaml(@opt)
  end

  def load(content)
    table = YAML.load(content)
    if table == false
      {}
    else
      table
    end
  end

  def marshal_dump_supports_canonical_option?
    false
  end

  EMPTY_MARSHAL_DATA = {}.to_yaml
  EMPTY_MARSHAL_CHECKSUM = Digest::MD5.digest(EMPTY_MARSHAL_DATA)
  def empty_marshal_data
    EMPTY_MARSHAL_DATA
  end
  def empty_marshal_checksum
    EMPTY_MARSHAL_CHECKSUM
  end
end
