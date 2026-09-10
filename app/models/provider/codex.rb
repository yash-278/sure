class Provider::Codex < Provider
  include LlmConcept

  class Deferred < Provider::Error
    attr_reader :resume_at

    def initialize(reason, resume_at: nil)
      @resume_at = resume_at
      super("ChatGPT work is paused: #{reason.to_s.humanize}", failure_code: reason)
    end
  end

  class << self
    def selected? = Setting.llm_provider == "codex"
    def configured? = %w[CODEX_ADAPTER_URL CODEX_ADAPTER_TOKEN CODEX_OWNER_USER_ID CODEX_OWNER_FAMILY_ID].all? { |key| ENV[key].present? }
    def owner = User.find_by(id: ENV["CODEX_OWNER_USER_ID"])
    def available_for?(user) = configured? && user.present? && user.id.to_s == ENV["CODEX_OWNER_USER_ID"] && user.family_id.to_s == ENV["CODEX_OWNER_FAMILY_ID"] && user.preview_features_enabled?
    def effective_model = Setting.codex_model.presence
  end

  def provider_name = "ChatGPT subscription"
  def supported_models_description = "Models available to the connected ChatGPT account"
  def supports_model?(_model) = self.class.configured?
  def supports_responses_endpoint? = false
  def supports_pdf_processing?(model: nil) = self.class.configured?
  def max_items_per_call = 25
  def context_window = 32_000
  def max_response_tokens = 8_000
  def max_history_tokens(instructions: nil) = 20_000
  def client = @client ||= Client.new

  def chat_response(prompt, model: nil, instructions: nil, functions: [], function_results: [], tool_choice: nil, messages: nil, conversation_history: [], streamer: nil, previous_response_id: nil, session_id: nil, user_identifier: nil, family: nil)
    with_provider_response do
      authorize!(family, interactive: user_identifier.present?)
      raise Error, "ChatGPT is restricted to its connected owner" if user_identifier.present? && user_identifier != Digest::SHA256.hexdigest(self.class.owner.id.to_s)
      allowed = tool_choice == :none ? [] : functions
      schema = object(answer: { type: "string" }, calls: { type: "array", maxItems: 8, items: object(name: { type: "string" }, arguments: { type: "string" }) })
      data = generate("#{instructions}\nReturn an answer or proposed function calls. Never claim a write succeeded before its tool result. Calls must use the supplied names and JSON arguments.\n#{ { prompt: prompt, history: messages || conversation_history, tool_results: function_results.map { |r| r.respond_to?(:to_h) ? r.to_h : r }, tools: allowed }.to_json }", schema, family, "chat:#{session_id}", interactive: user_identifier.present?, model: model)
      response_id = Digest::SHA256.hexdigest([ session_id, prompt, messages.to_json, function_results.to_json, data.to_json ].join(":"))
      requests = data.fetch("calls").each_with_index.map do |call, index|
        definition = allowed.find { |fn| fn[:name] == call.fetch("name") }
        raise Error, "ChatGPT requested an unavailable tool" unless definition
        arguments = JSON.parse(call.fetch("arguments"))
        JSON::Validator.validate!(definition.fetch(:params_schema).deep_stringify_keys, arguments)
        id = "#{response_id}-#{index}"
        ChatFunctionRequest.new(id: id, call_id: id, function_name: call["name"], function_args: arguments.to_json)
      end
      text = requests.empty? ? data.fetch("answer") : ""
      streamer&.call(ChatStreamChunk.new(type: "output_text", data: text, usage: nil)) if text.present?
      ChatResponse.new(id: response_id, model: model.presence || "codex", messages: text.present? ? [ ChatMessage.new(id: response_id, output_text: text) ] : [], function_requests: requests)
    end
  end

  def auto_categorize(transactions: [], user_categories: [], model: nil, family: nil, **)
    with_provider_response do
      authorize!(family)
      categories = user_categories.map { |c| c.is_a?(Hash) ? c[:name] || c["name"] : c }
      batch_rows(transactions, family, "categorisation", object(transaction_id: { type: "string" }, category_name: { type: [ "string", "null" ], enum: categories + [ nil ] }), "Categorise these transactions using only the supplied categories. Match IDs exactly; return null when uncertain. Categories: #{user_categories.to_json}", model).map { |row| AutoCategorization.new(**row.symbolize_keys) }
    end
  end

  def auto_detect_merchants(transactions: [], user_merchants: [], model: nil, family: nil, **)
    with_provider_response do
      authorize!(family)
      batch_rows(transactions, family, "merchant_detection", object(transaction_id: { type: "string" }, business_name: nullable_string, business_url: nullable_string), "Identify merchants without guessing. Use null for uncertain names or URLs. Existing merchants: #{user_merchants.to_json}", model).map { |row| AutoDetectedMerchant.new(**row.symbolize_keys) }
    end
  end

  def enhance_provider_merchants(merchants: [], model: nil, family: nil, **)
    with_provider_response do
      authorize!(family)
      batch_rows(merchants, family, "merchant_enrichment", object(merchant_id: { type: "string" }, business_url: nullable_string), "Return each merchant's official website only if known; otherwise null.", model).map { |row| EnhancedMerchant.new(**row.symbolize_keys) }
    end
  end

  def suggest_bill_setup(charges: [], categories: [], current_config: nil, model: nil, family: nil)
    with_provider_response do
      authorize!(family)
      properties = BillSetupSuggestion.members.to_h { |key| [ key, nullable_string ] }
      %i[amount confidence].each { |key| properties[key] = { type: [ "number", "null" ] } }
      %i[day_of_month weekday month_of_year].each { |key| properties[key] = { type: [ "integer", "null" ] } }
      properties[:amount][:minimum] = 0
      properties[:confidence].merge!(minimum: 0, maximum: 1)
      properties[:day_of_month].merge!(minimum: 1, maximum: 31)
      properties[:weekday].merge!(minimum: 0, maximum: 6)
      properties[:month_of_year].merge!(minimum: 1, maximum: 12)
      properties[:bill_type] = { type: [ "string", "null" ], enum: %w[subscription installment bill] + [ nil ] }
      properties[:autopay] = { type: [ "boolean", "null" ] }
      properties[:frequency] = { type: [ "string", "null" ], enum: %w[monthly weekly biweekly semimonthly quarterly semiannual annual] + [ nil ] }
      properties[:category_name] = { type: [ "string", "null" ], enum: categories + [ nil ] }
      result = generate("Suggest a recurring bill configuration from dated charges. Return null for uncertain or unchanged fields. Infer cadence from dates, use a positive amount, confidence 0 to 1, bill_type subscription/installment/bill.\n#{ { charges: charges, categories: categories, current_config: current_config }.to_json }", object(**properties), family, "bill_setup", model: model)
      BillSetupSuggestion.new(**result.symbolize_keys)
    end
  end

  def process_pdf(pdf_content:, model: nil, family: nil)
    with_provider_response do
      authorize!(family)
      result = Document.new(self, pdf_content, family, model).summary
      PdfProcessingResult.new(summary: result.fetch("summary"), document_type: result.fetch("document_type"), extracted_data: result.fetch("extracted_data"))
    end
  end

  def extract_bank_statement(pdf_content:, model: nil, family: nil)
    with_provider_response do
      authorize!(family)
      Document.new(self, pdf_content, family, model).extract
    end
  end

  def generate(prompt, schema, family, operation, interactive: false, model: nil, images: [])
    client.generate(prompt: prompt, schema: schema, family: family, operation: operation, model: model.presence == "codex" ? nil : model.presence || self.class.effective_model, images: images, interactive: interactive || Current.user.present?)
  end

  def object(**properties) = { type: "object", properties: properties, required: properties.keys.map(&:to_s), additionalProperties: false }
  def nullable_string = { type: [ "string", "null" ] }

  private
    def with_provider_response(**options, &block)
      result = super(error_transformer: ->(error) { error.is_a?(Deferred) ? error : default_error_transformer(error) }, &block)
      raise result.error if result.error.is_a?(Deferred)
      result
    end

    def authorize!(family, interactive: Current.user.present?)
      user = self.class.owner
      raise Error, "ChatGPT is restricted to its connected owner" unless self.class.available_for?(user) && family && user.family_id == family.id && user.ai_enabled?
      raise Error, "ChatGPT is restricted to its connected owner" if Current.user && Current.user.id != user.id
      raise Deferred.new(:background_paused) if !interactive && Setting.codex_background_paused
    end

    def batch_rows(rows, family, operation, row_schema, instructions, model)
      rows.each_slice(max_items_per_call).flat_map do |batch|
        data = generate("#{instructions}\n#{batch.to_json}", object(results: { type: "array", items: row_schema }), family, operation, model: model)
        id_key = row_schema[:properties].key?(:transaction_id) ? "transaction_id" : "merchant_id"
        expected = batch.map { |r| (r[:id] || r["id"] || r[id_key.to_sym] || r[id_key]).to_s }
        returned = data.fetch("results").map { |r| r.fetch(id_key) }
        raise Error, "ChatGPT returned mismatched record IDs" unless returned.sort == expected.sort
        data.fetch("results")
      end
    end
end
