
require 'rest-core'

class RestCore::Future
  include RestCore

  class Proxy < BasicObject
    def initialize future, target
      @future, @target = future, target
    end

    def method_missing msg, *args, &block
      @future.yield[@target].__send__(msg, *args, &block)
    end
  end

  def self.create *args, &block
    if Thread.current == Thread.main
      FutureFiber.new(*args, &block)
    else
      FutureQueue.new(*args, &block)
    end
  end

  def initialize env, k, immediate
    self.env       = env
    self.k         = k
    self.immediate = immediate
    self.response, self.body, self.status, self.headers, self.error = nil
  end

  def proxy_body   ; Proxy.new(self, RESPONSE_BODY   ); end
  def proxy_status ; Proxy.new(self, RESPONSE_STATUS ); end
  def proxy_headers; Proxy.new(self, RESPONSE_HEADERS); end

  def wait  ; raise NotImplementedError; end
  def resume; raise NotImplementedError; end

  def loaded?
    !!status
  end

  def yield
    wait
    callback
  end

  def callback
    self.response ||= k.call(
      env.merge(RESPONSE_BODY    => body  ,
                RESPONSE_STATUS  => status,
                RESPONSE_HEADERS => headers,
                FAIL             => ((env[FAIL]||[]) + [error]).compact,
                LOG              =>  (env[LOG] ||[]) +
                                      ["Future picked: #{self.class}"]))
  end

  def on_load body, status, headers
    env[TIMER].cancel if env[TIMER]
    self.body, self.status, self.headers = body, status, headers
    if immediate # no fibers are required in this case
      callback
    else
      resume
    end
  end

  def on_error error
    self.error = if error.kind_of?(Exception)
                   error
                 else
                   Error.new(error)
                 end
    on_load('', 0, {})
  end

  protected
  attr_accessor :env, :k, :immediate,
                :response, :body, :status, :headers, :error
end

require 'rest-core/app/future/future_fiber'
require 'rest-core/app/future/future_queue'
