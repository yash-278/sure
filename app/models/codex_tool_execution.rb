class CodexToolExecution < ApplicationRecord
  belongs_to :chat

  def self.once(chat, request)
    execution = create_or_find_by!(chat: chat, request_key: request.call_id)
    execution.with_lock do
      return execution.result if execution.result
      result = nil
      transaction(requires_new: true) do
        result = yield
        raise ActiveRecord::Rollback if result[:error] || result["error"] || result[:success] == false || result["success"] == false
      end
      execution.update!(result: result)
      result
    end
  end
end
