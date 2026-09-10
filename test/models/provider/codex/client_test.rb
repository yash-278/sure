require "test_helper"

class Provider::Codex::ClientTest < ActiveSupport::TestCase
  setup do
    @client = Provider::Codex::Client.new
    @arguments = { prompt: "Synthetic input", schema: { type: "object", properties: { amount: { type: "number" } }, required: [ "amount" ] }, family: families(:dylan_family), operation: "synthetic" }
  end

  test "structured results are validated before returning to financial code" do
    @client.stubs(:request).returns({ "status" => "completed", "result" => { "output" => { "amount" => "invented" } } })
    assert_raises(Provider::Codex::Error) { @client.generate(**@arguments) }
  end

  test "quota response preserves reset time for job suspension" do
    @client.stubs(:request).returns({ "status" => "waiting_quota", "error" => "quota_exhausted", "retryAt" => 1_800_000_000_000 })
    error = assert_raises(Provider::Codex::Deferred) { @client.generate(**@arguments) }
    assert_equal :quota_exhausted, error.failure_code
    assert_equal Time.at(1_800_000_000), error.resume_at
  end

  test "retrying identical input reuses the operation identity" do
    identities = []
    @client.stubs(:request).with { |_, _, payload| identities << payload[:id]; true }.returns({ "status" => "completed", "result" => { "output" => { "amount" => 25 } } })
    2.times { @client.generate(**@arguments) }
    assert_equal 1, identities.uniq.size
  end
end
