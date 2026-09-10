module Assistant::Provided
  extend ActiveSupport::Concern

  def get_model_provider(ai_model)
    return Provider::Registry.preferred_llm_provider if Provider::Codex.selected?

    registry.providers.find { |provider| provider.supports_model?(ai_model) }
  end

  private
    def registry
      @registry ||= Provider::Registry.for_concept(:llm)
    end
end
