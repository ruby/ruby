#
# YAML::Store
#
require 'yaml'
require 'pstore'

module YAML

	class Store < PStore
		#
		# Constructor
		# 
		def initialize( *o )
			@opt = YAML::DEFAULTS.dup
            if String === o.first
                super(o.pop)
            end
            if o.last.is_a? Hash
                @opt.update(o.pop)
            end
        end

		#
		# Override Pstore#transaction
		#
		def transaction
			raise YAML::Error, "nested transaction" if @transaction
			raise YAML::Error, "no filename for transaction" unless @filename
			begin
				@transaction = true
				value = nil
				backup = @filename+"~"
				if File::exist?(@filename)
					file = File::open(@filename, "rb+")
					orig = true
				else
					@table = {}
					file = File::open(@filename, "wb+")
					file.write( @table.to_yaml( @opt ) )
				end
				file.flock(File::LOCK_EX)
				if orig
					File::copy @filename, backup
					@table = YAML::load( file )
				end
				begin
					catch(:pstore_abort_transaction) do
						value = yield(self)
					end
				rescue Exception
					@abort = true
					raise
				ensure
					unless @abort
						begin
							file.rewind
							file.write( @table.to_yaml( @opt ) )
							file.truncate(file.pos)
						rescue
							File::rename backup, @filename if File::exist?(backup)
							raise
						end
					end
					@abort = false
				end
			ensure
				@table = nil
				@transaction = false
				file.close if file
			end
			value
		end
	end

end
