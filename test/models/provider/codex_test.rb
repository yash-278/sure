require "test_helper"

class Provider::CodexTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @provider = Provider::Codex.new
    Provider::Codex.stubs(:owner).returns(@user)
    Provider::Codex.stubs(:available_for?).with(@user).returns(true)
    @user.stubs(:ai_enabled?).returns(true)
    Setting.stubs(:codex_background_paused).returns(false)
    Current.stubs(:user).returns(nil)
  end

  test "rejects a different family before generation" do
    @provider.expects(:generate).never
    result = @provider.auto_categorize(family: families(:empty), transactions: [])
    assert_not result.success?
  end

  test "pauses background generation" do
    Setting.stubs(:codex_background_paused).returns(true)
    @provider.expects(:generate).never
    assert_raises(Provider::Codex::Deferred) { @provider.auto_categorize(family: @family) }
  end

  test "categorisation uses exact input identifiers" do
    @provider.stubs(:generate).returns({ "results" => [ { "transaction_id" => "wrong", "category_name" => "Food" } ] })
    result = @provider.auto_categorize(family: @family, transactions: [ { id: "correct" } ], user_categories: [ { name: "Food" } ])
    assert_not result.success?
  end

  test "categorisation returns the existing typed contract" do
    @provider.stubs(:generate).returns({ "results" => [ { "transaction_id" => "one", "category_name" => "Food" } ] })
    result = @provider.auto_categorize(family: @family, transactions: [ { id: "one" } ], user_categories: [ { name: "Food" } ])
    assert result.success?, result.error&.message
    assert_equal "Food", result.data.first.category_name
  end

  test "merchant detection returns the existing typed contract" do
    @provider.stubs(:generate).returns({ "results" => [ { "transaction_id" => "one", "business_name" => nil, "business_url" => nil } ] })
    result = @provider.auto_detect_merchants(family: @family, transactions: [ { id: "one" } ])
    assert result.success?, result.error&.message
    assert_nil result.data.first.business_url
  end

  test "merchant enrichment returns the existing typed contract" do
    @provider.stubs(:generate).returns({ "results" => [ { "merchant_id" => "one", "business_url" => nil } ] })
    result = @provider.enhance_provider_merchants(family: @family, merchants: [ { id: "one" } ])
    assert result.success?, result.error&.message
    assert_equal "one", result.data.first.merchant_id
  end

  test "bill setup returns nullable suggestion fields" do
    @provider.stubs(:generate).returns(Provider::LlmConcept::BillSetupSuggestion.members.to_h { |key| [ key.to_s, nil ] })
    result = @provider.suggest_bill_setup(family: @family)
    assert result.success?, result.error&.message
    assert_nil result.data.amount
  end

  test "chat rejects tools that were not advertised" do
    @provider.stubs(:generate).returns({ "answer" => "", "calls" => [ { "name" => "delete_all", "arguments" => "{}" } ] })
    result = @provider.chat_response("hello", family: @family)
    assert_not result.success?
  end

  test "chat refuses a different user's identifier in a worker" do
    @provider.expects(:generate).never
    result = @provider.chat_response("hello", family: @family, user_identifier: "another-user")
    assert_not result.success?
  end

  test "chat validates function arguments before returning requests" do
    @provider.stubs(:generate).returns({ "answer" => "", "calls" => [ { "name" => "lookup", "arguments" => '{"amount":"wrong"}' } ] })
    result = @provider.chat_response("hello", family: @family, functions: [ { name: "lookup", params_schema: @provider.object(amount: { type: "number" }) } ])
    assert_not result.success?
  end

  test "insight narration returns text without billed usage" do
    @provider.stubs(:generate).returns({ "answer" => "Recorded spending is 100.", "calls" => [] })
    assert_no_difference "LlmUsage.count" do
      result = @provider.chat_response("write insight", family: @family)
      assert result.success?, result.error&.message
      assert_equal "Recorded spending is 100.", result.data.messages.first.output_text
    end
  end

  test "selected subscription provider never falls back to an API provider" do
    Setting.stubs(:llm_provider).returns("codex")
    Provider::Codex.stubs(:configured?).returns(false)
    Provider::Registry.expects(:openai).never
    Provider::Registry.expects(:anthropic).never
    assert_nil Provider::Registry.preferred_llm_provider
  end
end
