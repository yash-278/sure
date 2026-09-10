require "net/http"
require "digest"
require "json-schema"

class Provider::Codex::Client
  def initialize(read_timeout: 35)
    @read_timeout = read_timeout
  end

  def request(method, path, body = nil)
    uri = URI(ENV.fetch("CODEX_ADAPTER_URL") + path)
    http = Net::HTTP.new(uri.host, uri.port, nil)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = @read_timeout
    request = { get: Net::HTTP::Get, post: Net::HTTP::Post, delete: Net::HTTP::Delete }.fetch(method).new(uri.request_uri)
    request["Authorization"] = "Bearer #{ENV.fetch('CODEX_ADAPTER_TOKEN')}"
    request["Content-Type"] = "application/json"
    request.body = body.to_json if body
    response = http.request(request)
    unless response.is_a?(Net::HTTPSuccess)
      code = JSON.parse(response.body)["error"] rescue nil
      raise Provider::Codex::Error.new("ChatGPT connection is unavailable", failure_code: code == "not_connected" ? :not_connected : code == "quota_exhausted" ? :quota_exhausted : :unreachable)
    end
    JSON.parse(response.body)
  rescue IOError, SystemCallError, Timeout::Error, JSON::ParserError
    raise Provider::Codex::Error, "ChatGPT connection is unavailable"
  end

  def generate(prompt:, schema:, family:, operation:, model: nil, images: [], interactive: false, reasoning: Current.ai_reasoning)
    payload = { prompt: prompt, schema: schema, images: images, model: model.presence, reasoning: reasoning, priority: interactive ? "interactive" : "background" }
    payload[:id] = Digest::SHA256.hexdigest([ family.id, operation, payload.to_json ].join(":"))
    result = request(:post, "/operations", payload)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 240
    until %w[completed failed interrupted cancelled waiting_quota].include?(result["status"])
      raise Provider::Codex::Error, "ChatGPT is still processing; retry to retrieve this operation" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 1
      result = request(:get, "/operations/#{payload[:id]}")
    end
    if result["error"].in?(%w[quota_exhausted not_connected])
      reset = result["retryAt"] ? Time.at(result["retryAt"] / 1000.0) : nil
      raise Provider::Codex::Deferred.new(result["error"].to_sym, resume_at: reset)
    end
    if result["error"] == "image_not_supported"
      raise Provider::Codex::Error, "The selected ChatGPT model cannot read scanned statement images. Choose an image-capable model in ChatGPT connection settings."
    end
    unless result["status"] == "completed"
      raise Provider::Codex::Error.new("ChatGPT operation #{result['status']}: #{result['error']}", failure_code: result["error"]&.to_sym)
    end
    output = result.fetch("result").fetch("output")
    JSON::Validator.validate!(schema.deep_stringify_keys, output)
    output
  rescue JSON::Schema::ValidationError
    raise Provider::Codex::Error, "ChatGPT returned invalid structured data"
  end
end
