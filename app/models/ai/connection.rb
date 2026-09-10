require "net/http"

class Ai::Connection
  NAMES = { "codex" => "ChatGPT subscription", "openai" => "OpenAI API", "anthropic" => "Anthropic API" }.freeze
  # Documented API capabilities. Unknown/custom models require an explicit test.
  OPENAI_CAPABILITIES = {
    "gpt-6-astra" => %w[low medium high xhigh max ultra],
    "gpt-5.5" => %w[none low medium high xhigh],
    "gpt-5.4" => %w[none low medium high xhigh],
    "gpt-5.4-mini" => %w[none low medium high xhigh],
    "gpt-5.4-nano" => %w[none low medium high xhigh],
    "gpt-4.1" => [], "gpt-4.1-mini" => [], "gpt-4.1-nano" => [], "gpt-4o" => [], "gpt-4o-mini" => []
  }.freeze

  attr_reader :id

  def initialize(id)
    raise Provider::Error, "Unknown connection" unless NAMES.key?(id)
    @id = id
  end

  def provider(model: nil)
    return Provider::Registry.get_provider(:codex) if id == "codex"
    return nil if credential.blank?
    if id == "openai"
      Provider::Openai.new(credential, uri_base: ENV["OPENAI_URI_BASE"].presence || Setting.openai_uri_base, model: model)
    else
      Provider::Anthropic.new(credential, base_url: ENV["ANTHROPIC_BASE_URL"].presence || Setting.anthropic_base_url, model: model)
    end
  end

  def models
    return codex_models if id == "codex"
    return [] unless credential.present?
    result = api_request("models")
    rows = result.fetch("data")
    previous_cursor = nil
    while result["has_more"]
      cursor = result["last_id"] || result.fetch("data").last&.fetch("id")
      raise Provider::Error, "Model catalogue is unavailable" if cursor.blank? || cursor == previous_cursor
      previous_cursor = cursor
      result = api_request("models?after_id=#{ERB::Util.url_encode(cursor)}")
      rows.concat(result.fetch("data"))
    end
    rows.map do |model|
      capability = id == "anthropic" ? model["capabilities"] : nil
      levels = if capability
        capability.fetch("effort", {}).filter_map { |key, value| key if value.is_a?(Hash) && value["supported"] }
      else
        official_openai? ? OPENAI_CAPABILITIES[model["id"]] : nil
      end
      { "id" => model.fetch("id"), "name" => model["display_name"] || model["id"],
        "images" => capability ? capability.dig("image_input", "supported") == true : !levels.nil?,
        "reasoning" => levels || [], "verified" => capability.present? || !levels.nil? }
    end.map { |model| model["verified"] ? model : manual_models.find { |manual| manual["id"] == model["id"] } || model }.concat(manual_models).uniq { |model| model["id"] }
  rescue Provider::Error
    raise if manual_models.empty?
    manual_models
  end

  def status
    result = if id == "codex"
      account_status = client.request(:get, "/account")
      return { state: "expired" } if account_status["reauthenticationRequired"]
      account = account_status["account"]
      return { state: "disconnected" } unless account
      limits = client.request(:get, "/limits")
      windows = [ limits.dig("rateLimits", "primary"), limits.dig("rateLimits", "secondary") ].compact
      exhausted = limits["ordinaryUsageAllowed"] == false || windows.any? { |w| w["usedPercent"].to_f >= 100 }
      { state: exhausted ? "quota" : "connected", account: account, windows: windows }
    else
      return { state: "disconnected" } unless credential.present?
      api_request("models")
      { state: "connected" }
    end
    Rails.cache.write("ai_connection_check/#{id}", Time.current, expires_in: 30.days)
    result.merge(checked_at: Time.current)
  rescue Provider::Error => error
    { state: error.failure_code == :not_connected ? "expired" : error.failure_code == :quota_exhausted ? "quota" : "unreachable", checked_at: Rails.cache.read("ai_connection_check/#{id}") }
  end

  def verify_manual!(model, reasoning:, images:)
    raise Provider::Error, "Manual models are for API connections" if id == "codex"
    raise Provider::Error, "Model identifier is required" if model.blank? || model.bytesize > 200
    # Verify structured output and, when requested, image input without financial data.
    text = "Return JSON with a single key ok set to true."
    if id == "openai"
      content = [ { type: "text", text: text } ]
      content << { type: "image_url", image_url: { url: test_image } } if images
      body = { model: model, messages: [ { role: "user", content: content } ], response_format: { type: "json_object" } }
      body[:reasoning_effort] = reasoning if reasoning.present?
      response = api_request("chat/completions", body: body)
      output = response.dig("choices", 0, "message", "content")
    else
      content = [ { type: "text", text: text } ]
      content << { type: "image", source: { type: "base64", media_type: "image/png", data: test_image.split(",").last } } if images
      body = { model: model, max_tokens: 1024, messages: [ { role: "user", content: content } ] }
      body[:output_config] = { effort: reasoning } if reasoning.present?
      response = api_request("messages", body: body)
      output = response.fetch("content").select { |item| item["type"] == "text" }.map { |item| item["text"] }.join
    end
    raise Provider::Error, "Model did not return valid structured output" unless JSON.parse(output) == { "ok" => true }
    entry = { "id" => model, "name" => model, "images" => images, "reasoning" => reasoning.present? ? [ reasoning ] : [], "verified" => true, "connection_fingerprint" => fingerprint }
    owner = Ai::Features.owner
    owner.with_lock do
      prefs = owner.preferences.deep_dup
      prefs["ai_manual_models"] ||= {}
      prefs["ai_manual_models"][id] = manual_models.reject { |item| item["id"] == model } + [ entry ]
      owner.update!(preferences: prefs)
    end
    entry
  rescue JSON::ParserError, TypeError
    raise Provider::Error, "Model did not return valid structured output"
  end

  private
    def client = Provider::Codex::Client.new(read_timeout: 5)

    def codex_models
      client.request(:get, "/models").fetch("data").map do |model|
        { "id" => model.fetch("id"), "name" => model["displayName"] || model["id"], "images" => model.fetch("inputModalities", []).include?("image"), "reasoning" => model.fetch("supportedReasoningEfforts", []).map { |level| level.fetch("reasoningEffort") }, "verified" => true }
      end
    end

    def manual_models
      (Ai::Features.owner&.preferences&.dig("ai_manual_models", id) || []).select { |model| model["connection_fingerprint"] == fingerprint }
    end

    def official_openai?
      base = ENV["OPENAI_URI_BASE"].presence || Setting.openai_uri_base.presence
      base.nil? || base.delete_suffix("/") == "https://api.openai.com/v1"
    end

    def fingerprint
      base = id == "openai" ? (ENV["OPENAI_URI_BASE"].presence || Setting.openai_uri_base) : (ENV["ANTHROPIC_BASE_URL"].presence || Setting.anthropic_base_url)
      Digest::SHA256.hexdigest([ id, base, credential ].join("\0"))
    end

    def credential
      if id == "openai"
        ENV["OPENAI_ACCESS_TOKEN"].presence || Setting.openai_access_token
      else
        ENV["ANTHROPIC_ACCESS_TOKEN"].presence || ENV["ANTHROPIC_API_KEY"].presence || Setting.anthropic_access_token
      end
    end

    def api_request(path, body: nil)
      base = if id == "openai"
        ENV["OPENAI_URI_BASE"].presence || Setting.openai_uri_base.presence || "https://api.openai.com/v1"
      else
        ENV["ANTHROPIC_BASE_URL"].presence || Setting.anthropic_base_url.presence || "https://api.anthropic.com/v1"
      end
      uri = URI("#{base.delete_suffix('/')}/#{path}")
      request = (body ? Net::HTTP::Post : Net::HTTP::Get).new(uri)
      request["Content-Type"] = "application/json"
      if id == "openai"
        request["Authorization"] = "Bearer #{credential}"
      else
        request["x-api-key"] = credential
        request["anthropic-version"] = "2023-06-01"
      end
      request.body = body.to_json if body
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: body ? 120 : 10) { |http| http.request(request) }
      unless response.is_a?(Net::HTTPSuccess)
        code = response.code.to_i
        raise Provider::Error.new("Connection request failed", failure_code: [ 401, 403 ].include?(code) ? :not_connected : code == 429 ? :quota_exhausted : :unreachable)
      end
      JSON.parse(response.body)
    rescue IOError, SystemCallError, Timeout::Error, JSON::ParserError
      raise Provider::Error.new("Connection unavailable", failure_code: :unreachable)
    end

    def test_image
      "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aEJkAAAAASUVORK5CYII="
    end
end
