require "application_system_test_case"

class CodexConnectionsTest < ApplicationSystemTestCase
  test "owner connects and enables subscription without an API key" do
    user = users(:family_admin)
    user.update!(preferences: { "preview_features_enabled" => true })
    Provider::Codex.stubs(:available_for?).returns(true)
    client = stub
    Provider::Codex::Client.stubs(:new).returns(client)
    client.stubs(:request).with(:get, "/account").returns({ "account" => { "type" => "chatgpt", "email" => "owner@example.com", "planType" => "pro" } })
    client.stubs(:request).with(:get, "/login").returns({ "state" => "connected" })
    client.stubs(:request).with(:get, "/limits").returns({})
    client.stubs(:request).with(:get, "/models").returns({ "data" => [ { "id" => "synthetic", "displayName" => "Synthetic" } ] })
    client.expects(:request).with(:post, "/settings", { paused: false }).returns({})
    sign_in user
    visit settings_codex_connection_path
    assert_text "Connected as owner@example.com"
    click_button "Save and use ChatGPT"
    assert_text "ChatGPT settings saved"
    assert_equal "codex", Setting.llm_provider
    save_screenshot(Rails.root.join("tmp/screenshots/codex-connection.png"))
  end
end
