require "application_system_test_case"

class AiFeaturesTest < ApplicationSystemTestCase
  test "owner configures one feature without enabling sharing or choosing other models" do
    user = users(:family_admin)
    user.update!(ai_enabled: false, preferences: { "preview_features_enabled" => true })
    env = ENV.to_h.slice("CODEX_OWNER_USER_ID", "CODEX_OWNER_FAMILY_ID", "CODEX_ADAPTER_URL", "CODEX_ADAPTER_TOKEN")
    ENV.update("CODEX_OWNER_USER_ID" => user.id, "CODEX_OWNER_FAMILY_ID" => user.family_id, "CODEX_ADAPTER_URL" => "http://adapter.test", "CODEX_ADAPTER_TOKEN" => "test")
    stub_request(:get, "http://adapter.test/account").to_return_json(body: { account: { type: "chatgpt", email: "owner@example.com" } })
    stub_request(:get, "http://adapter.test/limits").to_return_json(body: {})
    stub_request(:get, "http://adapter.test/models").to_return_json(body: { data: [ { id: "test-model", displayName: "Test model", inputModalities: [ "text", "image" ], supportedReasoningEfforts: [ { reasoningEffort: "low" }, { reasoningEffort: "high" } ] } ] })
    sign_in user
    visit settings_ai_feature_path(feature: "categorisation")
    assert_text "Transaction categorisation"
    select "Test model · ChatGPT subscription", from: "Model and connection"
    select "Low", from: "Reasoning level"
    click_button "Save feature"
    assert_text "AI settings saved"
    assert_equal "low", user.reload.preferences.dig("ai_features", "categorisation", "reasoning")
    assert_nil user.preferences.dig("ai_features", "chat")
    assert_not user.ai_enabled
    save_screenshot(Rails.root.join("tmp/screenshots/ai-feature-controls.png"))
  ensure
    env&.each_key { |key| ENV[key] = env[key] }
    %w[CODEX_OWNER_USER_ID CODEX_OWNER_FAMILY_ID CODEX_ADAPTER_URL CODEX_ADAPTER_TOKEN].each { |key| ENV.delete(key) unless env&.key?(key) }
  end
end
