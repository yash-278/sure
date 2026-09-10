# Binds a normal provider contract to an owner-approved feature selection.
class Ai::SelectedProvider < SimpleDelegator
  def initialize(user, feature, selection)
    @user, @feature, @selection = user, feature, selection
    @connection = Ai::Connection.new(selection.fetch("connection"))
    provider = @connection.provider(model: selection.fetch("model"))
    raise Provider::Codex::Deferred.new(:not_connected) unless provider
    super(provider)
  end

  Ai::Features::OPERATIONS.values.uniq.each do |operation|
    define_method(operation) do |*args, **kwargs|
      raise Provider::Error, "Wrong AI feature" unless Ai::Features::OPERATIONS.fetch(@feature) == operation
      raise Provider::Error, "AI sharing is off" unless @user.reload.ai_enabled? && (!Current.user || Current.user.id == @user.id)
      raise Provider::Error, "Wrong family" unless kwargs[:family]&.id == @user.family_id
      if !Current.user && Setting.codex_background_paused
        raise Provider::Codex::Deferred.new(:background_paused)
      end
      model = available_model
      replay = nil
      if operation == :chat_response && connection_id == "openai"
        @response_ids ||= []
        unless @response_ids.include?(kwargs[:previous_response_id])
          kwargs[:previous_response_id] = nil
          replay = kwargs[:messages]
        end
      end
      result = Current.set(ai_response_history: replay, ai_model_images: model["images"], ai_reasoning: @selection["reasoning"].presence) do
        __getobj__.public_send(operation, *args, **kwargs.merge(model: @selection.fetch("model")))
      end
      if !result.success? && result.error&.failure_code.in?(%i[not_connected quota_exhausted])
        raise Provider::Codex::Deferred.new(result.error.failure_code)
      end
      @response_ids << result.data.id if result.success? && operation == :chat_response && connection_id == "openai"
      result
    end
  end

  def supports_pdf_processing?(**) = available_model["images"]

  def selected_model = @selection.fetch("model")
  def connection_id = @connection.id

  private
    def available_model
      model = @connection.models.find { |item| item["id"] == selected_model }
      raise Provider::Codex::Deferred.new(:model_unavailable) unless model
      Ai::Features.new(@user).validate!(@feature, @selection, model)
      model
    rescue Provider::Codex::Deferred
      raise
    rescue Provider::Error => error
      raise Provider::Codex::Deferred.new(error.failure_code || :model_unavailable)
    end
end
