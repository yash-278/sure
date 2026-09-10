require "test_helper"

class Settings::AiFeaturesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @user.update!(preferences: { "preview_features_enabled" => true })
    sign_in @user
    @env = ENV.to_h.slice("CODEX_OWNER_USER_ID", "CODEX_OWNER_FAMILY_ID", "CODEX_ADAPTER_URL", "CODEX_ADAPTER_TOKEN")
    ENV.update("CODEX_OWNER_USER_ID" => @user.id, "CODEX_OWNER_FAMILY_ID" => @user.family_id, "CODEX_ADAPTER_URL" => "http://adapter.test", "CODEX_ADAPTER_TOKEN" => "test")
    stub_request(:get, "http://adapter.test/models").to_return_json(body: { data: [ { id: "test-model", displayName: "Test model", inputModalities: [ "text", "image" ], supportedReasoningEfforts: [ { reasoningEffort: "low" }, { reasoningEffort: "high" } ] } ] })
  end

  teardown do
    %w[CODEX_OWNER_USER_ID CODEX_OWNER_FAMILY_ID CODEX_ADAPTER_URL CODEX_ADAPTER_TOKEN].each { |key| ENV[key] = @env[key] }
  end

  test "owner must explicitly select reasoning and no global default is copied" do
    patch settings_ai_feature_path, params: { feature: "categorisation", configuration: { connection: "codex", model: "test-model", reasoning: "" } }
    assert_response :unprocessable_entity
    assert_empty @user.reload.preferences.fetch("ai_features", {})
    patch settings_ai_feature_path, params: { feature: "categorisation", configuration: { connection: "codex", model: "test-model", reasoning: "low" } }
    assert_redirected_to settings_ai_feature_path(feature: "categorisation")
    assert_equal "low", @user.reload.preferences.dig("ai_features", "categorisation", "reasoning")
    assert_nil @user.preferences.dig("ai_features", "chat")
  end

  test "another owner cannot change the connection's configuration" do
    ENV["CODEX_OWNER_USER_ID"] = SecureRandom.uuid
    patch settings_ai_feature_path, params: { feature: "chat", configuration: { connection: "codex", model: "test-model", reasoning: "high" } }
    assert_response :forbidden
  end
  test "saved categorisation routes the real workflow to selected model and reasoning" do
    @user.update!(ai_enabled: true)
    patch settings_ai_feature_path, params: { feature: "categorisation", configuration: { connection: "codex", model: "test-model", reasoning: "low" } }
    transaction = @user.family.transactions.first
    transaction.update!(category: nil)
    category = @user.family.categories.first
    request = stub_request(:post, "http://adapter.test/operations").with { |req|
      payload = JSON.parse(req.body)
      payload["model"] == "test-model" && payload["reasoning"] == "low"
    }.to_return_json(body: { status: "completed", result: { output: { results: [ { transaction_id: transaction.id, category_name: category.name } ] } } })
    @user.family.auto_categorize_transactions([ transaction.id ])
    assert_requested request
    assert_equal category.id, transaction.reload.category_id
  end

  test "settings show feature detail and live connection state without sending financial data" do
    stub_request(:get, "http://adapter.test/account").to_return_json(body: { account: { type: "chatgpt", email: "owner@example.com" } })
    stub_request(:get, "http://adapter.test/limits").to_return_json(body: { ordinaryUsageAllowed: true })
    get settings_ai_feature_path(feature: "statement_extraction")
    assert_response :success
    assert_select "h2", text: "Statement extraction"
    assert_select "select[name='choice']"
    assert_includes response.body, "authentication checked"
    assert_includes response.body, "Not configured"
    assert_not_requested :post, "http://adapter.test/operations"
  end

  test "sharing off blocks configured categorisation before generation" do
    @user.update!(ai_enabled: false)
    patch settings_ai_feature_path, params: { feature: "categorisation", configuration: { connection: "codex", model: "test-model", reasoning: "low" } }
    transaction = @user.family.transactions.first
    transaction.update!(category: nil)
    assert_raises(Provider::Error) { @user.family.auto_categorize_transactions([ transaction.id ]) }
    assert_not_requested :post, "http://adapter.test/operations"
  end

  test "API categorisation uses explicit connection despite global subscription selection" do
    @user.update!(ai_enabled: true)
    Setting.stubs(:openai_access_token).returns("synthetic-api-key")
    Setting.stubs(:llm_provider).returns("codex")
    stub_request(:get, "https://api.openai.com/v1/models").to_return_json(body: { data: [ { id: "gpt-5.4" } ] })
    patch settings_ai_feature_path, params: { feature: "categorisation", configuration: { connection: "openai", model: "gpt-5.4", reasoning: "low" } }
    assert_response :redirect
    transaction = @user.family.transactions.first
    transaction.update!(category: nil)
    category = @user.family.categories.first
    request = stub_request(:post, "https://api.openai.com/v1/responses").with { |req|
      payload = JSON.parse(req.body)
      payload["model"] == "gpt-5.4" && payload.dig("reasoning", "effort") == "low"
    }.to_return_json(body: { output: [ { type: "message", content: [ { type: "output_text", text: { categorizations: [ { transaction_id: transaction.id, category_name: category.name } ] }.to_json } ] } ] })
    @user.family.auto_categorize_transactions([ transaction.id ])
    assert_requested request
    assert_not_requested :post, "http://adapter.test/operations"
    assert_equal category.id, transaction.reload.category_id
  end

  test "a removed saved model does not fall back" do
    @user.update!(ai_enabled: true)
    patch settings_ai_feature_path, params: { feature: "categorisation", configuration: { connection: "codex", model: "test-model", reasoning: "low" } }
    stub_request(:get, "http://adapter.test/models").to_return_json(body: { data: [] })
    transaction = @user.family.transactions.first
    transaction.update!(category: nil)
    assert_raises(Provider::Error) { @user.family.auto_categorize_transactions([ transaction.id ]) }
    assert_not_requested :post, "http://adapter.test/operations"
    assert_nil transaction.reload.category_id
  end

  test "PDF selection requires images and sharing never changes when saving features" do
    @user.update!(ai_enabled: false)
    stub_request(:get, "http://adapter.test/models").to_return_json(body: { data: [ { id: "text-only", inputModalities: [ "text" ] } ] })
    patch settings_ai_feature_path, params: { feature: "statement_extraction", configuration: { connection: "codex", model: "text-only" } }
    assert_response :unprocessable_entity
    assert_not @user.reload.ai_enabled
    assert_empty @user.preferences.fetch("ai_features", {})
  end
  test "custom model discovery requires verification even with a familiar name" do
    Setting.stubs(:openai_access_token).returns("synthetic")
    Setting.stubs(:openai_uri_base).returns("https://custom.test/v1")
    stub_request(:get, "https://custom.test/v1/models").to_return_json(body: { data: [ { id: "gpt-4.1" } ] })
    patch settings_ai_feature_path, params: { feature: "chat", configuration: { connection: "openai", model: "gpt-4.1" } }
    assert_response :unprocessable_entity
    stub_request(:post, "https://custom.test/v1/chat/completions").to_return_json(body: { choices: [ { message: { content: '{"ok":true}' } } ] })
    post settings_ai_feature_path, params: { connection: "openai", manual_model: "gpt-4.1", confirm_usage: "1" }
    assert_response :redirect
    patch settings_ai_feature_path, params: { feature: "chat", configuration: { connection: "openai", model: "gpt-4.1" } }
    assert_response :redirect
    assert_equal "openai", @user.reload.preferences.dig("ai_features", "chat", "connection")
  end

  test "OpenAI chat replays stored history then chains its own tool response" do
    @user.update!(ai_enabled: true)
    Setting.stubs(:openai_access_token).returns("synthetic")
    stub_request(:get, "https://api.openai.com/v1/models").to_return_json(body: { data: [ { id: "gpt-5.4" } ] })
    patch settings_ai_feature_path, params: { feature: "chat", configuration: { connection: "openai", model: "gpt-5.4", reasoning: "low" } }
    first = stub_request(:post, "https://api.openai.com/v1/responses").with { |req|
      body = JSON.parse(req.body)
      body["previous_response_id"].nil? && body["input"].first["content"] == "Earlier question"
    }.to_return_json(body: { id: "response-one", output: [ { type: "function_call", id: "call-item", call_id: "call-one", name: "get_accounts", arguments: "{}" } ] })
    provider = Ai::Features.new(@user.reload).provider(:chat)
    result = provider.chat_response("Now", model: "ignored", family: @user.family, previous_response_id: "other-provider", messages: [ { role: "user", content: "Earlier question" }, { role: "user", content: "Now" } ])
    assert result.success?, result.error&.message
    second = stub_request(:post, "https://api.openai.com/v1/responses").with { |req|
      body = JSON.parse(req.body)
      body["previous_response_id"] == "response-one" && body["input"].any? { |item| item["type"] == "function_call_output" && item["call_id"] == "call-one" }
    }.to_return_json(body: { id: "response-two", output: [ { type: "message", id: "answer", content: [ { type: "output_text", text: "Done" } ] } ] })
    result = provider.chat_response("Now", model: "ignored", family: @user.family, previous_response_id: "response-one", function_results: [ { call_id: "call-one", output: [] } ])
    assert result.success?, result.error&.message
    assert_requested first
    assert_requested second
  end
  test "unavailable PDF model leaves import recoverable without ledger writes" do
    @user.update!(ai_enabled: true)
    Setting.stubs(:codex_background_paused).returns(false)
    patch settings_ai_feature_path, params: { feature: "pdf_summary", configuration: { connection: "codex", model: "test-model", reasoning: "low" } }
    pdf = imports(:pdf)
    pdf.pdf_file.attach(io: StringIO.new(file_fixture("imports/codex_text_statement.pdf").binread), filename: "statement.pdf", content_type: "application/pdf")
    stub_request(:get, "http://adapter.test/models").to_return_json(body: { data: [] })
    assert_no_difference "Entry.count" do
      assert_difference "CodexDeferredJob.count", 1 do
        ProcessPdfJob.perform_now(pdf)
      end
    end
    assert_equal "pending", pdf.reload.status
    assert_equal "model_unavailable", CodexDeferredJob.last.reason
    assert_not_requested :post, "http://adapter.test/operations"
  end

  test "PDF summary runs independently and defers unconfigured statement extraction" do
    @user.update!(ai_enabled: true)
    Setting.stubs(:codex_background_paused).returns(false)
    patch settings_ai_feature_path, params: { feature: "pdf_summary", configuration: { connection: "codex", model: "test-model", reasoning: "low" } }
    pdf = imports(:pdf)
    pdf.pdf_file.attach(io: StringIO.new(file_fixture("imports/codex_text_statement.pdf").binread), filename: "statement.pdf", content_type: "application/pdf")
    output = {
      summary: "Synthetic statement", document_type: "bank_statement", bank_name: "Test",
      account_holder: nil, account_number: nil, currency: "USD", opening_balance: "100.00", closing_balance: "100.00",
      period: { start_date: "2026-01-01", end_date: "2026-01-31" }, warnings: [], transactions: []
    }
    request = stub_request(:post, "http://adapter.test/operations").to_return_json(body: { status: "completed", result: { output: output } })
    assert_no_difference "Entry.count" do
      ProcessPdfJob.perform_now(pdf)
    end
    assert_requested request, times: 1
    assert_equal "Synthetic statement", pdf.reload.ai_summary
    assert_equal "pending", pdf.status
    assert_equal "feature_unconfigured", CodexDeferredJob.last.reason
  end
  test "connection outages offer a recheck without asking for new credentials" do
    stub_request(:get, "http://adapter.test/account").to_return(status: 503, body: '{"error":"unavailable"}')
    get settings_ai_feature_path
    assert_response :success
    assert_includes response.body, "Service unreachable"
    assert_select "a", text: "Check connections again"
    assert_select "a", text: "Reconnect ChatGPT", count: 0
  end
  test "merchant bill insight and extraction workflows retain independent selections" do
    @user.update!(ai_enabled: true)
    Setting.stubs(:codex_background_paused).returns(false)
    features = %w[merchant_detection merchant_enrichment bill_suggestions insight_narration statement_extraction]
    stub_request(:get, "http://adapter.test/models").to_return_json(body: { data: features.map { |feature| { id: feature, inputModalities: %w[text image], supportedReasoningEfforts: [ { reasoningEffort: "low" } ] } } })
    features.each do |feature|
      patch settings_ai_feature_path, params: { feature: feature, configuration: { connection: "codex", model: feature, reasoning: "low" } }
      assert_response :redirect
    end
    transaction = @user.family.transactions.first
    transaction.update!(merchant: nil)
    detection = feature_response("merchant_detection", { results: [ { transaction_id: transaction.id, business_name: "Synthetic store", business_url: "https://example.com" } ] })
    Family::AutoMerchantDetector.new(@user.family, transaction_ids: [ transaction.id ]).auto_detect
    assert_requested detection
    assert_equal "Synthetic store", transaction.reload.merchant.name

    merchant = transaction.merchant
    merchant.update!(website_url: nil)
    enrichment = feature_response("merchant_enrichment", { results: [ { merchant_id: merchant.id, business_url: "https://example.com" } ] })
    ProviderMerchant::Enhancer.new(@user.family).enhance
    assert_requested enrichment
    assert_equal "https://example.com", merchant.reload.website_url

    suggestion = Provider::LlmConcept::BillSetupSuggestion.members.index_with { nil }.merge(name: "Synthetic bill", amount: 40.0, frequency: "monthly")
    bill = feature_response("bill_suggestions", suggestion)
    result = RecurringTransaction::AiSetupSuggester.new(@user.family, user: @user).suggest_from_entries([ transaction.entry ])
    assert_requested bill
    assert_equal "Synthetic bill", result.name

    narration = feature_response("insight_narration", { answer: "Synthetic narration.", calls: [] })
    insight = Insight::Generator::GeneratedInsight.new(insight_type: "idle_cash", priority: "low", title: "Synthetic", template_key: "idle_cash", facts: { account: "Synthetic", balance: "$100.00", idle_days: 60 }, metadata: {}, currency: "USD", period_start: nil, period_end: nil, dedup_key: "synthetic")
    assert_equal "Synthetic narration.", Insight::BodyWriter.new(@user.family).write(insight)
    assert_requested narration

    extraction = feature_response("statement_extraction", {
      summary: "Synthetic statement", document_type: "bank_statement", bank_name: "Test",
      account_holder: nil, account_number: nil, currency: "USD", opening_balance: "100.00", closing_balance: "100.00",
      period: { start_date: "2026-01-01", end_date: "2026-01-31" }, warnings: [], transactions: []
    })
    pdf = imports(:pdf)
    pdf.pdf_file.attach(io: StringIO.new(file_fixture("imports/codex_text_statement.pdf").binread), filename: "statement.pdf", content_type: "application/pdf")
    pdf.update!(document_type: "bank_statement")
    assert_no_difference "Entry.count" do
      pdf.extract_transactions
    end
    assert_requested extraction
  end

  private
    def feature_response(model, output)
      stub_request(:post, "http://adapter.test/operations").with { |request|
        payload = JSON.parse(request.body)
        payload["model"] == model && payload["reasoning"] == "low"
      }.to_return_json(body: { status: "completed", result: { output: output } })
    end
end
