# Adds feature reasoning at the SDK request boundary, including batch helpers.
class Ai::ReasoningClient < SimpleDelegator
  def initialize(client, protocol, endpoint = nil)
    @protocol, @endpoint = protocol, endpoint
    super(client)
  end

  def responses = self.class.new(__getobj__.responses, @protocol, :responses)
  def messages = self.class.new(__getobj__.messages, @protocol, :messages)

  def chat(parameters:)
    translate_errors { __getobj__.chat(parameters: parameters_with_reasoning(parameters)) }
  end

  def create(**parameters)
    translate_errors do
      if @protocol == :openai
        __getobj__.create(**parameters.merge(parameters: parameters_with_reasoning(parameters.fetch(:parameters))))
      else
        __getobj__.create(**parameters_with_reasoning(parameters))
      end
    end
  end

  def stream(**parameters)
    translate_errors { __getobj__.stream(**parameters_with_reasoning(parameters)) }
  end

  private
    def translate_errors
      yield
    rescue StandardError => error
      status = error.respond_to?(:status) ? error.status : error.respond_to?(:response) ? error.response&.dig(:status) : nil
      code = case status.to_i
      when 401, 403 then :not_connected
      when 429 then :quota_exhausted
      end
      raise Provider::Error.new("AI connection requires attention", failure_code: code) if code
      raise
    end

    def parameters_with_reasoning(parameters)
      effort = Current.ai_reasoning
      return parameters unless effort
      if @protocol == :anthropic
        parameters.merge(output_config: { effort: effort })
      elsif @endpoint == :responses
        parameters.merge(reasoning: { effort: effort })
      else
        parameters.except(:temperature).merge(reasoning_effort: effort)
      end
    end
end
