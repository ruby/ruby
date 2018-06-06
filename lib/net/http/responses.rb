# frozen_string_literal: true
# :stopdoc:
# https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
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
  EXCEPTION_TYPE = Net::HTTPClientException   # for backward compatibility
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
class Net::HTTPProcessing < Net::HTTPInformation         # 102
  HAS_BODY = false
end
class Net::HTTPEarlyHints < Net::HTTPInformation         # 103 - RFC 8297
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
class Net::HTTPMultiStatus < Net::HTTPSuccess                   # 207 - RFC 4918
  HAS_BODY = true
end
class Net::HTTPAlreadyReported < Net::HTTPSuccess               # 208 - RFC 5842
  HAS_BODY = true
end
class Net::HTTPIMUsed < Net::HTTPSuccess                        # 226 - RFC 3229
  HAS_BODY = true
end

class Net::HTTPMultipleChoices < Net::HTTPRedirection    # 300
  HAS_BODY = true
end
Net::HTTPMultipleChoice = Net::HTTPMultipleChoices
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
# 306 Switch Proxy - no longer unused
class Net::HTTPTemporaryRedirect < Net::HTTPRedirection  # 307
  HAS_BODY = true
end
class Net::HTTPPermanentRedirect < Net::HTTPRedirection  # 308
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
class Net::HTTPRequestTimeout < Net::HTTPClientError                # 408
  HAS_BODY = true
end
Net::HTTPRequestTimeOut = Net::HTTPRequestTimeout
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
class Net::HTTPPayloadTooLarge < Net::HTTPClientError               # 413
  HAS_BODY = true
end
Net::HTTPRequestEntityTooLarge = Net::HTTPPayloadTooLarge
class Net::HTTPURITooLong < Net::HTTPClientError                    # 414
  HAS_BODY = true
end
Net::HTTPRequestURITooLong = Net::HTTPURITooLong
Net::HTTPRequestURITooLarge = Net::HTTPRequestURITooLong
class Net::HTTPUnsupportedMediaType < Net::HTTPClientError          # 415
  HAS_BODY = true
end
class Net::HTTPRangeNotSatisfiable < Net::HTTPClientError           # 416
  HAS_BODY = true
end
Net::HTTPRequestedRangeNotSatisfiable = Net::HTTPRangeNotSatisfiable
class Net::HTTPExpectationFailed < Net::HTTPClientError             # 417
  HAS_BODY = true
end
# 418 I'm a teapot - RFC 2324; a joke RFC
# 420 Enhance Your Calm - Twitter
class Net::HTTPMisdirectedRequest < Net::HTTPClientError            # 421 - RFC 7540
  HAS_BODY = true
end
class Net::HTTPUnprocessableEntity < Net::HTTPClientError           # 422 - RFC 4918
  HAS_BODY = true
end
class Net::HTTPLocked < Net::HTTPClientError                        # 423 - RFC 4918
  HAS_BODY = true
end
class Net::HTTPFailedDependency < Net::HTTPClientError              # 424 - RFC 4918
  HAS_BODY = true
end
# 425 Unordered Collection - existed only in draft
class Net::HTTPUpgradeRequired < Net::HTTPClientError               # 426 - RFC 2817
  HAS_BODY = true
end
class Net::HTTPPreconditionRequired < Net::HTTPClientError          # 428 - RFC 6585
  HAS_BODY = true
end
class Net::HTTPTooManyRequests < Net::HTTPClientError               # 429 - RFC 6585
  HAS_BODY = true
end
class Net::HTTPRequestHeaderFieldsTooLarge < Net::HTTPClientError   # 431 - RFC 6585
  HAS_BODY = true
end
class Net::HTTPUnavailableForLegalReasons < Net::HTTPClientError    # 451 - RFC 7725
  HAS_BODY = true
end
# 444 No Response - Nginx
# 449 Retry With - Microsoft
# 450 Blocked by Windows Parental Controls - Microsoft
# 499 Client Closed Request - Nginx

class Net::HTTPInternalServerError < Net::HTTPServerError           # 500
  HAS_BODY = true
end
class Net::HTTPNotImplemented < Net::HTTPServerError                # 501
  HAS_BODY = true
end
class Net::HTTPBadGateway < Net::HTTPServerError                    # 502
  HAS_BODY = true
end
class Net::HTTPServiceUnavailable < Net::HTTPServerError            # 503
  HAS_BODY = true
end
class Net::HTTPGatewayTimeout < Net::HTTPServerError                # 504
  HAS_BODY = true
end
Net::HTTPGatewayTimeOut = Net::HTTPGatewayTimeout
class Net::HTTPVersionNotSupported < Net::HTTPServerError           # 505
  HAS_BODY = true
end
class Net::HTTPVariantAlsoNegotiates < Net::HTTPServerError         # 506
  HAS_BODY = true
end
class Net::HTTPInsufficientStorage < Net::HTTPServerError           # 507 - RFC 4918
  HAS_BODY = true
end
class Net::HTTPLoopDetected < Net::HTTPServerError                  # 508 - RFC 5842
  HAS_BODY = true
end
# 509 Bandwidth Limit Exceeded - Apache bw/limited extension
class Net::HTTPNotExtended < Net::HTTPServerError                   # 510 - RFC 2774
  HAS_BODY = true
end
class Net::HTTPNetworkAuthenticationRequired < Net::HTTPServerError # 511 - RFC 6585
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
    '102' => Net::HTTPProcessing,
    '103' => Net::HTTPEarlyHints,

    '200' => Net::HTTPOK,
    '201' => Net::HTTPCreated,
    '202' => Net::HTTPAccepted,
    '203' => Net::HTTPNonAuthoritativeInformation,
    '204' => Net::HTTPNoContent,
    '205' => Net::HTTPResetContent,
    '206' => Net::HTTPPartialContent,
    '207' => Net::HTTPMultiStatus,
    '208' => Net::HTTPAlreadyReported,
    '226' => Net::HTTPIMUsed,

    '300' => Net::HTTPMultipleChoices,
    '301' => Net::HTTPMovedPermanently,
    '302' => Net::HTTPFound,
    '303' => Net::HTTPSeeOther,
    '304' => Net::HTTPNotModified,
    '305' => Net::HTTPUseProxy,
    '307' => Net::HTTPTemporaryRedirect,
    '308' => Net::HTTPPermanentRedirect,

    '400' => Net::HTTPBadRequest,
    '401' => Net::HTTPUnauthorized,
    '402' => Net::HTTPPaymentRequired,
    '403' => Net::HTTPForbidden,
    '404' => Net::HTTPNotFound,
    '405' => Net::HTTPMethodNotAllowed,
    '406' => Net::HTTPNotAcceptable,
    '407' => Net::HTTPProxyAuthenticationRequired,
    '408' => Net::HTTPRequestTimeout,
    '409' => Net::HTTPConflict,
    '410' => Net::HTTPGone,
    '411' => Net::HTTPLengthRequired,
    '412' => Net::HTTPPreconditionFailed,
    '413' => Net::HTTPPayloadTooLarge,
    '414' => Net::HTTPURITooLong,
    '415' => Net::HTTPUnsupportedMediaType,
    '416' => Net::HTTPRangeNotSatisfiable,
    '417' => Net::HTTPExpectationFailed,
    '421' => Net::HTTPMisdirectedRequest,
    '422' => Net::HTTPUnprocessableEntity,
    '423' => Net::HTTPLocked,
    '424' => Net::HTTPFailedDependency,
    '426' => Net::HTTPUpgradeRequired,
    '428' => Net::HTTPPreconditionRequired,
    '429' => Net::HTTPTooManyRequests,
    '431' => Net::HTTPRequestHeaderFieldsTooLarge,
    '451' => Net::HTTPUnavailableForLegalReasons,

    '500' => Net::HTTPInternalServerError,
    '501' => Net::HTTPNotImplemented,
    '502' => Net::HTTPBadGateway,
    '503' => Net::HTTPServiceUnavailable,
    '504' => Net::HTTPGatewayTimeout,
    '505' => Net::HTTPVersionNotSupported,
    '506' => Net::HTTPVariantAlsoNegotiates,
    '507' => Net::HTTPInsufficientStorage,
    '508' => Net::HTTPLoopDetected,
    '510' => Net::HTTPNotExtended,
    '511' => Net::HTTPNetworkAuthenticationRequired,
  }
end

# :startdoc:
