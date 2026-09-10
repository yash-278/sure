class CodexToolApproval < ApplicationRecord
  belongs_to :user
  belongs_to :chat
  encrypts :arguments_json
  validates :status, inclusion: { in: %w[pending approved rejected] }

  def self.for_request(chat, request)
    json = JSON.parse(request.function_args).sort.to_h.to_json
    digest = Digest::SHA256.hexdigest([ request.function_name, json ].join(":"))
    find_or_create_by!(chat: chat, digest: digest) do |approval|
      approval.user = chat.user
      approval.function_name = request.function_name
      approval.arguments_json = json
    end
  end

  def approve!
    with_lock do
      return result unless status == "pending"
      raise Provider::Codex::Error, "Connection is not available" unless Provider::Codex.selected? && Provider::Codex.available_for?(user) && user.ai_enabled?
      function = Assistant.function_classes(user).find { |klass| klass.name == function_name }&.new(user)
      raise Provider::Codex::Error, "This action is no longer available" unless function
      arguments = JSON.parse(arguments_json)
      require "json-schema"
      JSON::Validator.validate!(function.params_schema.deep_stringify_keys, arguments)
      output = nil
      transaction(requires_new: true) do
        output = function.call(arguments)
        raise ActiveRecord::Rollback if output[:error] || output["error"] || output[:success] == false || output["success"] == false
      end
      update!(status: "approved", result: output)
      output
    end
  end
end
