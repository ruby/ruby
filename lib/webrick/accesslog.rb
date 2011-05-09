#--
# accesslog.rb -- Access log handling utilities
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2002 keita yamaguchi
# Copyright (c) 2002 Internet Programming with Ruby writers
#
# $IPR: accesslog.rb,v 1.1 2002/10/01 17:16:32 gotoyuzo Exp $

module WEBrick
  module AccessLog
    class AccessLogError < StandardError; end

    CLF_TIME_FORMAT     = "[%d/%b/%Y:%H:%M:%S %Z]"
    COMMON_LOG_FORMAT   = "%h %l %u %t \"%r\" %s %b"
    CLF                 = COMMON_LOG_FORMAT
    REFERER_LOG_FORMAT  = "%{Referer}i -> %U"
    AGENT_LOG_FORMAT    = "%{User-Agent}i"
    COMBINED_LOG_FORMAT = "#{CLF} \"%{Referer}i\" \"%{User-agent}i\""

    module_function

    # This format specification is a subset of mod_log_config of Apache.
    #   http://httpd.apache.org/docs/mod/mod_log_config.html#formats
    def setup_params(config, req, res)
      params = Hash.new("")
      params["a"] = req.peeraddr[3]
      params["b"] = res.sent_size
      params["e"] = ENV
      params["f"] = res.filename || ""
      params["h"] = req.peeraddr[2]
      params["i"] = req
      params["l"] = "-"
      params["m"] = req.request_method
      params["n"] = req.attributes
      params["o"] = res
      params["p"] = req.port
      params["q"] = req.query_string
      params["r"] = req.request_line.sub(/\x0d?\x0a\z/o, '')
      params["s"] = res.status       # won't support "%>s"
      params["t"] = req.request_time
      params["T"] = Time.now - req.request_time
      params["u"] = req.user || "-"
      params["U"] = req.unparsed_uri
      params["v"] = config[:ServerName]
      params
    end

    def format(format_string, params)
      format_string.gsub(/\%(?:\{(.*?)\})?>?([a-zA-Z%])/){
         param, spec = $1, $2
         case spec[0]
         when ?e, ?i, ?n, ?o
           raise AccessLogError,
             "parameter is required for \"#{spec}\"" unless param
           (param = params[spec][param]) ? escape(param) : "-"
         when ?t
           params[spec].strftime(param || CLF_TIME_FORMAT)
         when ?p
           case param
           when 'remote'
             escape(params["i"].peeraddr[1].to_s)
           else
             escape(params["p"].to_s)
           end
         when ?%
           "%"
         else
           escape(params[spec].to_s)
         end
      }
    end

    def escape(data)
      if data.tainted?
        data.gsub(/[[:cntrl:]\\]+/) {$&.dump[1...-1]}.untaint
      else
        data
      end
    end
  end
end
