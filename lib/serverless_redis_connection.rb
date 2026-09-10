require "redis-client"
require "redis_client/ruby_connection"

# RedisClient's 15-second TCP probes prevent Railway's 5–10 minute idle sleep.
# Opt in per web process; keep normal Redis command timeouts and reconnects.
class ServerlessRedisConnection < RedisClient::RubyConnection
  IDLE_SECONDS = 900

  def self.install!
    RedisClient.register_driver(:serverless) { self }
    RedisClient.default_driver = :serverless
  end

  private

    def enable_socket_keep_alive(socket)
      super
      if Socket.const_defined?(:TCP_KEEPIDLE)
        socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_KEEPIDLE, IDLE_SECONDS)
      end
    end
end
