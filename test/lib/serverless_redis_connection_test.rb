require "test_helper"
require "serverless_redis_connection"

class ServerlessRedisConnectionTest < ActiveSupport::TestCase
  test "allows the idle sleep window without disabling TCP keepalive" do
    skip "Linux TCP_KEEPIDLE required" unless Socket.const_defined?(:TCP_KEEPIDLE)

    socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    ServerlessRedisConnection.allocate.send(:enable_socket_keep_alive, socket)

    assert_equal 1, socket.getsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE).int
    assert_equal 900, socket.getsockopt(Socket::IPPROTO_TCP, Socket::TCP_KEEPIDLE).int
    assert_equal 15, socket.getsockopt(Socket::IPPROTO_TCP, Socket::TCP_KEEPINTVL).int
  ensure
    socket&.close
  end

  test "does not change ordinary worker Redis connections" do
    skip "Linux TCP_KEEPIDLE required" unless Socket.const_defined?(:TCP_KEEPIDLE)

    socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    RedisClient::RubyConnection.allocate.send(:enable_socket_keep_alive, socket)

    assert_equal 15, socket.getsockopt(Socket::IPPROTO_TCP, Socket::TCP_KEEPIDLE).int
  ensure
    socket&.close
  end
end
