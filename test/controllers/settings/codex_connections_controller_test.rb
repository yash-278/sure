require "test_helper"

class Settings::CodexConnectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @user.update!(preferences: { "preview_features_enabled" => true })
    sign_in @user
    Provider::Codex.stubs(:available_for?).returns(true)
    @client = mock
    Provider::Codex::Client.stubs(:new).returns(@client)
  end

  test "non-owner cannot view the connection" do
    Provider::Codex.stubs(:available_for?).returns(false)
    @client.expects(:request).never
    get settings_codex_connection_path
    assert_response :forbidden
  end

  test "disconnected connection shows login without credentials" do
    @client.expects(:request).with(:get, "/account").returns({ "account" => nil })
    @client.expects(:request).with(:get, "/login").returns({ "state" => "idle" })
    get settings_codex_connection_path
    assert_response :success
    assert_includes response.body, "Connect ChatGPT"
  end

  test "connected page shows model and quota" do
    @client.expects(:request).with(:get, "/account").returns({ "account" => { "type" => "chatgpt", "email" => "owner@example.com", "planType" => "pro" } })
    @client.expects(:request).with(:get, "/login").returns({ "state" => "connected" })
    @client.expects(:request).with(:get, "/limits").returns({ "rateLimits" => { "primary" => { "usedPercent" => 10, "windowDurationMins" => 300, "resetsAt" => 1_800_000_000 } } })
    @client.expects(:request).with(:get, "/models").returns({ "data" => [ { "id" => "test", "displayName" => "Test" } ] })
    get settings_codex_connection_path
    assert_response :success
    assert_includes response.body, "10% used"
    assert_select "select[name='connection[model]']"
  end

  test "pending login shows the device code" do
    @client.expects(:request).with(:get, "/account").returns({ "account" => nil })
    @client.expects(:request).with(:get, "/login").returns({ "state" => "pending", "userCode" => "TEST-CODE1" })
    get settings_codex_connection_path
    assert_response :success
    assert_includes response.body, "TEST-CODE1"
  end

  test "disconnect never switches to an API provider" do
    Setting.stubs(:llm_provider).returns("codex")
    Setting.expects(:llm_provider=).never
    @client.expects(:request).with(:delete, "/account").returns({})
    delete settings_codex_connection_path
    assert_redirected_to settings_codex_connection_path
  end

  test "non-owner cannot change or disconnect the connection" do
    Provider::Codex.stubs(:available_for?).returns(false)
    @client.expects(:request).never
    post settings_codex_connection_path
    assert_response :forbidden
    patch settings_codex_connection_path, params: { cancel_login: "1" }
    assert_response :forbidden
    delete settings_codex_connection_path
    assert_response :forbidden
  end

  test "connection mutations require CSRF protection" do
    ActionController::Base.allow_forgery_protection = true
    @client.expects(:request).never
    post settings_codex_connection_path
    assert_response :unprocessable_entity
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  teardown do
    Setting.codex_background_paused = false
  end
end
