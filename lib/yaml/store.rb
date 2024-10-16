# frozen_string_literal: false
#
# YAML::Store
#
require 'yaml'

begin
  require 'pstore'
rescue LoadError
end

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
  #   initialize( file_name, thread_safe = false, yaml_opts = {} )
  #
  # Creates a new YAML::Store object, which will store data in +file_name+.
  # If the file does not already exist, it will be created.
  #
  # YAML::Store objects are always reentrant. But if _thread_safe_ is set to true,
  # then it will become thread-safe at the cost of a minor performance hit.
  #
  # Options passed in through +yaml_opts+ will be used when converting the
  # store to YAML via Hash#to_yaml().
  def initialize( *o )
    @opt = {}
    if o.last.is_a? Hash
      @opt.update(o.pop)
    end
    super(*o)
  end

  # :stopdoc:

  def dump(table)
    table.to_yaml(@opt)
  end

  def load(content)
    table =  if YAML.respond_to?(:safe_load)
      if Psych::VERSION >= "3.1"
        YAML.safe_load(content, permitted_classes: [Symbol])
      else
        YAML.safe_load(content, [Symbol])
      end
    else
      YAML.load(content)
    end
    if table == false || table == nil
      {}
    else
      table
    end
  end

  def marshal_dump_supports_canonical_option?
    false
  end

  def empty_marshal_data
    {}.to_yaml(@opt)
  end
  def empty_marshal_checksum
    CHECKSUM_ALGO.digest(empty_marshal_data)
  end
end if defined?(::PStore)
