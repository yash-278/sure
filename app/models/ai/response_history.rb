# Replays stored chat history on a new API connection without reusing another
# connection's response ID. In-flight turns continue using their own response ID.
class Ai::ResponseHistory
  def initialize(messages)
    @messages = messages
  end

  def input
    @messages.flat_map do |message|
      row = message.symbolize_keys
      if row[:role] == "tool"
        [ { type: "function_call_output", call_id: row[:tool_call_id], output: row[:content] } ]
      else
        items = row[:content].present? ? [ { role: row[:role], content: row[:content] } ] : []
        Array(row[:tool_calls]).each do |call|
          call = call.deep_symbolize_keys
          items << { type: "function_call", call_id: call[:id], name: call.dig(:function, :name), arguments: call.dig(:function, :arguments) }
        end
        items
      end
    end
  end
end
