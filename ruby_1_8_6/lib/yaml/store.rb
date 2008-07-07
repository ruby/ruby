#
# YAML::Store
#
require 'yaml'
require 'pstore'

class YAML::Store < PStore
  def initialize( *o )
    @opt = YAML::DEFAULTS.dup
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
    YAML::load(content)
  end

  def load_file(file)
    YAML::load(file)
  end
end
