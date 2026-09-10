class Settings::AiFeaturesController < ApplicationController
  layout "settings"
  helper Settings::AiFeaturesHelper
  before_action :require_preview_features!
  before_action :ensure_owner

  def show
    @feature = params[:feature].presence_in(Ai::Features::OPERATIONS.keys) || "chat"
    @features = Ai::Features.new(Current.user)
    @selection = @features.configuration(@feature).dup
    if params.key?(:choice)
      @selection = choice_attributes(params[:choice])
    end
    @connections = Ai::Connection::NAMES.map do |id, name|
      connection = Ai::Connection.new(id)
      status = connection.status
      models = begin
        connection.models
      rescue Provider::Error
        []
      end
      { id: id, name: name, status: status, models: models }
    end
    @model = @connections.find { |c| c[:id] == @selection["connection"] }&.dig(:models)&.find { |m| m["id"] == @selection["model"] }
  end

  def update
    if params[:controls]
      data = params.require(:controls).permit(:sharing, :paused)
      sharing = ActiveModel::Type::Boolean.new.cast(data[:sharing])
      paused = ActiveModel::Type::Boolean.new.cast(data[:paused])
      # Persist revocation first, so an unavailable adapter cannot retain consent.
      Current.user.update!(ai_enabled: false) unless sharing
      client = Provider::Codex::Client.new
      client.request(:delete, "/operations") unless sharing
      client.request(:post, "/settings", { paused: !sharing || paused })
      Setting.codex_background_paused = paused
      Current.user.update!(ai_enabled: true) if sharing
      CodexDeferredJob.resume_ready if sharing && !paused
    else
      data = params.require(:configuration).permit(:connection, :model, :reasoning, :choice).to_h
      data.merge!(choice_attributes(data.delete("choice"))) if data.key?("choice")
      Ai::Features.new(Current.user).save!(params[:feature], data)
      CodexResumeJobsJob.perform_later if Current.user.ai_enabled?
    end
    redirect_to settings_ai_feature_path(feature: params[:feature]), notice: t(".saved")
  rescue Provider::Error => error
    render plain: error.message, status: :unprocessable_entity
  end

  def create
    raise Provider::Error, "Confirm synthetic test usage" unless params[:confirm_usage] == "1"
    if params[:manual_model].present?
      Ai::Connection.new(params[:connection]).verify_manual!(params[:manual_model], reasoning: params[:reasoning], images: params[:images] == "1")
    else
      selection = Ai::Features.new(Current.user).configuration(params[:feature])
      raise Provider::Error, "Select and save a model first" if selection.blank?
      connection = Ai::Connection.new(selection.fetch("connection"))
      if connection.id == "codex"
        Provider::Codex::Client.new.generate(prompt: "Return ok true.", schema: { type: "object", properties: { ok: { type: "boolean", enum: [ true ] } }, required: [ "ok" ], additionalProperties: false }, family: Current.family, operation: "synthetic_test:#{SecureRandom.uuid}", model: selection["model"], interactive: true, reasoning: selection["reasoning"])
      else
        connection.verify_manual!(selection.fetch("model"), reasoning: selection["reasoning"], images: params[:feature].in?(%w[pdf_summary statement_extraction]))
      end
    end
    verified = params[:manual_model].present? ? params[:connection] : selection["connection"]
    CodexDeferredJob.resume_ready(verified_connection: verified)
    redirect_to settings_ai_feature_path(feature: params[:feature]), notice: t(".tested")
  rescue Provider::Error => error
    redirect_to settings_ai_feature_path(feature: params[:feature]), alert: error.message
  end

  private
    def choice_attributes(choice)
      connection, model = choice.to_s.split(":", 2)
      { "connection" => connection, "model" => model }
    end

    def ensure_owner
      head :forbidden unless Provider::Codex.available_for?(Current.user) && Current.user.admin?
    end
end
