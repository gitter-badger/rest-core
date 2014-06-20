
require 'rest-core/middleware'
require 'rest-core/util/json'

class RestCore::JsonResponse
  def self.members; [:json_response]; end
  include RestCore::Middleware

  class ParseError < Json.const_get(:ParseError)
    attr_reader :cause, :body
    def initialize cause, body
      super("#{cause.message}\nOriginal text: #{body}")
      @cause, @body = cause, body
    end
  end

  JSON_RESPONSE_HEADER = {'Accept' => 'application/json'}.freeze

  def call env, &k
    return app.call(env, &k) if env[DRY]
    return app.call(env, &k) unless json_response(env)

    app.call(env.merge(REQUEST_HEADERS =>
      JSON_RESPONSE_HEADER.merge(env[REQUEST_HEADERS]||{}))){ |response|
        yield(process(response))
      }
  end

  def process response
    body = response[RESPONSE_BODY]
    response.merge(RESPONSE_BODY => Json.decode("[#{body}]").first)
    # [this].first is not needed for yajl-ruby
  rescue Json.const_get(:ParseError) => error
    fail(response, ParseError.new(error, body))
  end
end
