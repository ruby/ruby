#
# YAML::Store
#
require 'yaml'
require 'pstore'

class YAML::Store < PStore
  def initialize( *o )
    @opt = {}
    if String === o.first
      super(o.shift)
    end
    if o.last.is_a? Hash
      @opt.update(o.pop)
    end
  end

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
