# The owner's explicit choices are also used by family background jobs.
class Ai::Features
  OPERATIONS = {
    "chat" => :chat_response,
    "categorisation" => :auto_categorize,
    "merchant_detection" => :auto_detect_merchants,
    "merchant_enrichment" => :enhance_provider_merchants,
    "bill_suggestions" => :suggest_bill_setup,
    "insight_narration" => :chat_response,
    "pdf_summary" => :process_pdf,
    "statement_extraction" => :extract_bank_statement
  }.freeze

  JOB_FEATURES = {
    "AutoCategorizeJob" => %w[categorisation],
    "AutoDetectMerchantsJob" => %w[merchant_detection],
    "EnhanceProviderMerchantsJob" => %w[merchant_enrichment],
    "ProcessPdfJob" => %w[pdf_summary]
  }.freeze

  def self.job_features(job)
    if job.class.name == "ProcessPdfJob" && job.arguments.first.ai_processed? && job.arguments.first.statement_with_transactions?
      %w[statement_extraction]
    else
      JOB_FEATURES.fetch(job.class.name, [])
    end
  end

  def self.owner
    Provider::Codex.owner
  end

  def self.managed?(family)
    owner && family && owner.family_id == family.id
  end

  def self.provider(feature, family:)
    return Provider::Registry.preferred_llm_provider unless managed?(family)
    return nil unless owner.preview_features_enabled?
    new(owner).provider(feature)
  end

  def initialize(user)
    @user = user
  end

  def configuration(feature)
    @user.preferences.fetch("ai_features", {}).fetch(feature.to_s, {})
  end

  def save!(feature, attributes)
    raise Provider::Error, "Unknown AI feature" unless OPERATIONS.key?(feature)
    selection = attributes.to_h.slice("connection", "model", "reasoning")
    if selection["model"].present?
      connection = Ai::Connection.new(selection.fetch("connection"))
      model = connection.models.find { |item| item["id"] == selection["model"] }
      raise Provider::Error, "Model unavailable" unless model
      validate!(feature, selection, model)
    end
    @user.with_lock do
      preferences = @user.preferences.deep_dup
      preferences["ai_features"] ||= {}
      if selection["model"].blank?
        preferences["ai_features"].delete(feature)
      else
        preferences["ai_features"][feature] = selection
      end
      @user.update!(preferences: preferences)
    end
  end

  def provider(feature)
    selection = configuration(feature)
    return nil if selection.blank?
    Ai::SelectedProvider.new(@user, feature.to_s, selection)
  end

  def validate!(feature, selection, model)
    raise Provider::Error, "Verify this model before selecting it" if model["verified"] == false
    if feature.in?(%w[pdf_summary statement_extraction]) && !model.fetch("images", false)
      raise Provider::Error, "Image input is required for PDF features"
    end
    levels = model.fetch("reasoning", [])
    unless levels.empty? ? selection["reasoning"].blank? : levels.include?(selection["reasoning"])
      raise Provider::Error, "Choose a supported reasoning level explicitly"
    end
  end
end
