require "test_helper"

class CodexToolExecutionTest < ActiveSupport::TestCase
  setup do
    @chat = chats(:one)
    @request = Provider::LlmConcept::ChatFunctionRequest.new(id: "retry", call_id: "retry", function_name: "test", function_args: "{}")
  end

  test "completed financial writes are not repeated" do
    calls = 0
    2.times do
      result = CodexToolExecution.once(@chat, @request) { calls += 1; { "success" => true } }
      assert_equal true, result["success"]
    end
    assert_equal 1, calls
  end

  test "failed tools roll back partial writes and retain their result" do
    original = @chat.title
    CodexToolExecution.once(@chat, @request) do
      @chat.update!(title: "Partial write")
      { "success" => false }
    end
    assert_equal original, @chat.reload.title
    assert_equal({ "success" => false }, CodexToolExecution.once(@chat, @request) { flunk "Repeated failed write" })
  end
end
