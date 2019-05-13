# MIT License
# See https://github.com/divoxx/ruby-php-serialization/blob/master/LICENSE.txt

class PhpSerialization::Unserializer
rule

  data            : null    ';'  { @object = val[0] }
                  | bool    ';'  { @object = val[0] }
                  | integer ';'  { @object = val[0] }
                  | double  ';'  { @object = val[0] }
                  | string  ';'  { @object = val[0] }
                  | assoc_array  { @object = val[0] }
                  | object       { @object = val[0] }
                  ;

  null            : 'N' { result = nil }
                  ;

  bool            : 'b' ':' NUMBER { result = Integer(val[2]) > 0 }
                  ;

  integer         : 'i' ':' NUMBER { result = Integer(val[2]) }
                  ;

  double          : 'd' ':' NUMBER { result = Float(val[2]) }
                  ;

  string          : 's' ':' NUMBER ':' STRING { result = val[4] }
                  ;

  object          : 'O' ':' NUMBER ':' STRING ':' NUMBER ':' '{' attribute_list '}'
                    {
                      if eval("defined?(#{val[4]})")
                        result = Object.const_get(val[4]).new

                        val[9].each do |(attr_name, value)|
                          # Protected and private attributes will have a \0..\0 prefix
                          attr_name = attr_name.gsub(/\A\\0[^\\]+\\0/, '')
                          result.instance_variable_set("@#{attr_name}", value)
                        end
                      else
                        klass_name = val[4].gsub(/^Struct::/, '')
                        attr_names, values = [], []

                        val[9].each do |(attr_name, value)|
                          # Protected and private attributes will have a \0..\0 prefix
                          attr_names << attr_name.gsub(/\A\\0[^\\]+\\0/, '')
                          values << value
                        end

                        result = Struct.new(klass_name, *attr_names).new(*values)
                        result.instance_variable_set("@_php_class", klass_name)
                      end
                    }
                  ;

  attribute_list  : attribute_list attribute { result = val[0] << val[1] }
                  |                          { result = [] }
                  ;

  attribute       : data data { result = val }
                  ;

  assoc_array     : 'a' ':' NUMBER ':' '{' attribute_list '}'
                    {
                      # Checks if the keys are a sequence of integers
                      idx = -1
                      arr = val[5].all? { |(k,v)| k == (idx += 1) }

                      if arr
                        result = val[5].map { |(k,v)| v }
                      else
                        result = Hash[val[5]]
                      end
                    }
                  ;

end

---- header ----
require 'php_serialization/tokenizer'

---- inner ----
  def initialize(tokenizer_klass = Tokenizer)
    @tokenizer_klass = tokenizer_klass
  end

  def run(string)
    @tokenizer = @tokenizer_klass.new(string)
    yyparse(@tokenizer, :each)
    return @object
  ensure
    @tokenizer = nil
  end

  def next_token
    @tokenizer.next_token
  end
