require "test_helper"

class CodexToolApprovalTest < ActiveSupport::TestCase
  test "approval executes stored arguments only once" do
    chat = chats(:one)
    request = Provider::LlmConcept::ChatFunctionRequest.new(id: "one", call_id: "one", function_name: "record_valuation", function_args: '{"amount":100}')
    approval = CodexToolApproval.for_request(chat, request)
    function = mock
    function.stubs(:params_schema).returns({ type: "object" })
    function.expects(:call).with({ "amount" => 100 }).once.returns({ "success" => true })
    klass = mock
    klass.stubs(:name).returns("record_valuation")
    klass.stubs(:new).with(chat.user).returns(function)
    Assistant.stubs(:function_classes).with(chat.user).returns([ klass ])
    Provider::Codex.stubs(:selected?).returns(true)
    Provider::Codex.stubs(:available_for?).with(chat.user).returns(true)
    2.times { assert_equal({ "success" => true }, approval.approve!) }
  end

  test "different arguments require a distinct approval" do
    chat = chats(:one)
    first = Provider::LlmConcept::ChatFunctionRequest.new(id: "one", call_id: "one", function_name: "record_valuation", function_args: '{"amount":100}')
    second = first.with(function_args: '{"amount":200}')
    assert_not_equal CodexToolApproval.for_request(chat, first).id, CodexToolApproval.for_request(chat, second).id
  end
end
