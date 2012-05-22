# :stopdoc:
class Net::HTTPUnknownResponse < Net::HTTPResponse
  HAS_BODY = true
  EXCEPTION_TYPE = Net::HTTPError
end
class Net::HTTPInformation < Net::HTTPResponse           # 1xx
  HAS_BODY = false
  EXCEPTION_TYPE = Net::HTTPError
end
class Net::HTTPSuccess < Net::HTTPResponse               # 2xx
  HAS_BODY = true
  EXCEPTION_TYPE = Net::HTTPError
end
class Net::HTTPRedirection < Net::HTTPResponse           # 3xx
  HAS_BODY = true
  EXCEPTION_TYPE = Net::HTTPRetriableError
end
class Net::HTTPClientError < Net::HTTPResponse           # 4xx
  HAS_BODY = true
  EXCEPTION_TYPE = Net::HTTPServerException   # for backward compatibility
end
class Net::HTTPServerError < Net::HTTPResponse           # 5xx
  HAS_BODY = true
  EXCEPTION_TYPE = Net::HTTPFatalError    # for backward compatibility
end

class Net::HTTPContinue < Net::HTTPInformation           # 100
  HAS_BODY = false
end
class Net::HTTPSwitchProtocol < Net::HTTPInformation     # 101
  HAS_BODY = false
end

class Net::HTTPOK < Net::HTTPSuccess                            # 200
  HAS_BODY = true
end
class Net::HTTPCreated < Net::HTTPSuccess                       # 201
  HAS_BODY = true
end
class Net::HTTPAccepted < Net::HTTPSuccess                      # 202
  HAS_BODY = true
end
class Net::HTTPNonAuthoritativeInformation < Net::HTTPSuccess   # 203
  HAS_BODY = true
end
class Net::HTTPNoContent < Net::HTTPSuccess                     # 204
  HAS_BODY = false
end
class Net::HTTPResetContent < Net::HTTPSuccess                  # 205
  HAS_BODY = false
end
class Net::HTTPPartialContent < Net::HTTPSuccess                # 206
  HAS_BODY = true
end

class Net::HTTPMultipleChoice < Net::HTTPRedirection     # 300
  HAS_BODY = true
end
class Net::HTTPMovedPermanently < Net::HTTPRedirection   # 301
  HAS_BODY = true
end
class Net::HTTPFound < Net::HTTPRedirection              # 302
  HAS_BODY = true
end
Net::HTTPMovedTemporarily = Net::HTTPFound
class Net::HTTPSeeOther < Net::HTTPRedirection           # 303
  HAS_BODY = true
end
class Net::HTTPNotModified < Net::HTTPRedirection        # 304
  HAS_BODY = false
end
class Net::HTTPUseProxy < Net::HTTPRedirection           # 305
  HAS_BODY = false
end
# 306 unused
class Net::HTTPTemporaryRedirect < Net::HTTPRedirection  # 307
  HAS_BODY = true
end

class Net::HTTPBadRequest < Net::HTTPClientError                    # 400
  HAS_BODY = true
end
class Net::HTTPUnauthorized < Net::HTTPClientError                  # 401
  HAS_BODY = true
end
class Net::HTTPPaymentRequired < Net::HTTPClientError               # 402
  HAS_BODY = true
end
class Net::HTTPForbidden < Net::HTTPClientError                     # 403
  HAS_BODY = true
end
class Net::HTTPNotFound < Net::HTTPClientError                      # 404
  HAS_BODY = true
end
class Net::HTTPMethodNotAllowed < Net::HTTPClientError              # 405
  HAS_BODY = true
end
class Net::HTTPNotAcceptable < Net::HTTPClientError                 # 406
  HAS_BODY = true
end
class Net::HTTPProxyAuthenticationRequired < Net::HTTPClientError   # 407
  HAS_BODY = true
end
class Net::HTTPRequestTimeOut < Net::HTTPClientError                # 408
  HAS_BODY = true
end
class Net::HTTPConflict < Net::HTTPClientError                      # 409
  HAS_BODY = true
end
class Net::HTTPGone < Net::HTTPClientError                          # 410
  HAS_BODY = true
end
class Net::HTTPLengthRequired < Net::HTTPClientError                # 411
  HAS_BODY = true
end
class Net::HTTPPreconditionFailed < Net::HTTPClientError            # 412
  HAS_BODY = true
end
class Net::HTTPRequestEntityTooLarge < Net::HTTPClientError         # 413
  HAS_BODY = true
end
class Net::HTTPRequestURITooLong < Net::HTTPClientError             # 414
  HAS_BODY = true
end
Net::HTTPRequestURITooLarge = Net::HTTPRequestURITooLong
class Net::HTTPUnsupportedMediaType < Net::HTTPClientError          # 415
  HAS_BODY = true
end
class Net::HTTPRequestedRangeNotSatisfiable < Net::HTTPClientError  # 416
  HAS_BODY = true
end
class Net::HTTPExpectationFailed < Net::HTTPClientError             # 417
  HAS_BODY = true
end

class Net::HTTPInternalServerError < Net::HTTPServerError   # 500
  HAS_BODY = true
end
class Net::HTTPNotImplemented < Net::HTTPServerError        # 501
  HAS_BODY = true
end
class Net::HTTPBadGateway < Net::HTTPServerError            # 502
  HAS_BODY = true
end
class Net::HTTPServiceUnavailable < Net::HTTPServerError    # 503
  HAS_BODY = true
end
class Net::HTTPGatewayTimeOut < Net::HTTPServerError        # 504
  HAS_BODY = true
end
class Net::HTTPVersionNotSupported < Net::HTTPServerError   # 505
  HAS_BODY = true
end

class Net::HTTPResponse
  CODE_CLASS_TO_OBJ = {
    '1' => Net::HTTPInformation,
    '2' => Net::HTTPSuccess,
    '3' => Net::HTTPRedirection,
    '4' => Net::HTTPClientError,
    '5' => Net::HTTPServerError
  }
  CODE_TO_OBJ = {
    '100' => Net::HTTPContinue,
    '101' => Net::HTTPSwitchProtocol,

    '200' => Net::HTTPOK,
    '201' => Net::HTTPCreated,
    '202' => Net::HTTPAccepted,
    '203' => Net::HTTPNonAuthoritativeInformation,
    '204' => Net::HTTPNoContent,
    '205' => Net::HTTPResetContent,
    '206' => Net::HTTPPartialContent,

    '300' => Net::HTTPMultipleChoice,
    '301' => Net::HTTPMovedPermanently,
    '302' => Net::HTTPFound,
    '303' => Net::HTTPSeeOther,
    '304' => Net::HTTPNotModified,
    '305' => Net::HTTPUseProxy,
    '307' => Net::HTTPTemporaryRedirect,

    '400' => Net::HTTPBadRequest,
    '401' => Net::HTTPUnauthorized,
    '402' => Net::HTTPPaymentRequired,
    '403' => Net::HTTPForbidden,
    '404' => Net::HTTPNotFound,
    '405' => Net::HTTPMethodNotAllowed,
    '406' => Net::HTTPNotAcceptable,
    '407' => Net::HTTPProxyAuthenticationRequired,
    '408' => Net::HTTPRequestTimeOut,
    '409' => Net::HTTPConflict,
    '410' => Net::HTTPGone,
    '411' => Net::HTTPLengthRequired,
    '412' => Net::HTTPPreconditionFailed,
    '413' => Net::HTTPRequestEntityTooLarge,
    '414' => Net::HTTPRequestURITooLong,
    '415' => Net::HTTPUnsupportedMediaType,
    '416' => Net::HTTPRequestedRangeNotSatisfiable,
    '417' => Net::HTTPExpectationFailed,

    '500' => Net::HTTPInternalServerError,
    '501' => Net::HTTPNotImplemented,
    '502' => Net::HTTPBadGateway,
    '503' => Net::HTTPServiceUnavailable,
    '504' => Net::HTTPGatewayTimeOut,
    '505' => Net::HTTPVersionNotSupported
  }
end

# :startdoc:

