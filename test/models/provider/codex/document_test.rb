require "test_helper"

class Provider::Codex::DocumentTest < ActiveSupport::TestCase
  setup do
    @provider = Provider::Codex.new
    @family = users(:family_admin).family
    @data = {
      "summary" => "Synthetic bank statement", "document_type" => "bank_statement", "bank_name" => "Test",
      "account_holder" => nil, "account_number" => nil, "currency" => "USD", "opening_balance" => "100.00", "closing_balance" => "125.00",
      "period" => { "start_date" => "2026-01-01", "end_date" => "2026-01-31" }, "warnings" => [],
      "transactions" => [ { "date" => "2026-01-15", "amount" => "25.00", "name" => "Refund", "category" => nil, "notes" => nil, "page" => 1 } ]
    }
    @provider.stubs(:generate).returns(@data)
    page = stub(text: "Synthetic bank statement with a refund and unambiguous dates and amounts.")
    PDF::Reader.stubs(:new).returns(stub(page_count: 1, pages: [ page ]))
    @document = Provider::Codex::Document.new(@provider, "synthetic", @family, nil)
  end

  test "extraction preserves exact decimal amounts and page provenance without ledger writes" do
    assert_no_difference "Entry.count" do
      result = @document.extract
      assert_equal "25.00", result[:transactions].first[:amount]
      assert_includes result[:transactions].first[:notes], "page 1"
      assert_empty result[:warnings]
    end
  end

  test "ambiguous dates stop extraction" do
    @data["transactions"][0]["date"] = "01/02/2026"
    assert_raises(Provider::Codex::Error) { @document.extract }
  end

  test "non-numeric amounts stop extraction" do
    @data["transactions"][0]["amount"] = "unknown"
    assert_raises(Provider::Codex::Error) { @document.extract }
  end

  test "mismatched balances are flagged without adjustments" do
    @data["closing_balance"] = "200.00"
    result = @document.extract
    assert_equal 1, result[:transactions].size
    assert result[:warnings].any? { |w| w.include?("do not reconcile") }
  end

  test "identical rows are preserved and flagged for review" do
    @data["transactions"] << @data["transactions"][0].dup
    result = @document.extract
    assert_equal 2, result[:transactions].size
    assert result[:warnings].any? { |w| w.include?("Identical") }
  end
  test "real text PDF extracts without image rendering" do
    PDF::Reader.unstub(:new)
    @provider.expects(:generate).with { |prompt, _, _, _, **options| prompt.include?("Opening balance") && options[:images].empty? }.returns(@data)
    document = Provider::Codex::Document.new(@provider, file_fixture("imports/codex_text_statement.pdf").read, @family, nil)
    assert_equal "25.00", document.extract[:transactions].first[:amount]
  end

  test "scanned PDF renders image input and removes temporary files" do
    PDF::Reader.unstub(:new)
    before = Dir.glob(File.join(Dir.tmpdir, "sure-statement-*-#{Process.pid}-*"))
    @provider.expects(:generate).with { |_, _, _, _, **options| options[:images].one? && options[:images].first.start_with?("data:image/png;base64,") }.returns(@data)
    document = Provider::Codex::Document.new(@provider, file_fixture("imports/codex_scanned_statement.pdf").read, @family, nil)
    assert_equal "25.00", document.extract[:transactions].first[:amount]
    assert_equal before, Dir.glob(File.join(Dir.tmpdir, "sure-statement-*-#{Process.pid}-*"))
  end

  test "unknown currencies and out of range page references are rejected" do
    @data["currency"] = "XYZ"
    assert_raises(Provider::Codex::Error) { @document.extract }
    @data["currency"] = "USD"
    @data["transactions"][0]["page"] = 7
    assert_raises(Provider::Codex::Error) { @document.extract }
  end
end
