class Settings::CodexConnectionsController < ApplicationController
  layout "settings"
  before_action :require_preview_features!
  before_action :ensure_owner

  def show
    @account = client.request(:get, "/account")["account"]
    @login = client.request(:get, "/login")
    @account = nil if @login["state"] == "pending"
    CodexResumeJobsJob.perform_later if @account && Ai::Features.managed?(Current.family) && Current.user.ai_enabled?
    @limits = client.request(:get, "/limits") if @account
    @models = @account ? client.request(:get, "/models").fetch("data") : []
  rescue Provider::Codex::Error
    @unavailable = true
    @models = []
  end

  def create
    client.request(:delete, "/login")
    client.request(:post, "/login")
    redirect_to settings_codex_connection_path
  rescue Provider::Codex::Error
    redirect_to settings_codex_connection_path, alert: t(".failed")
  end

  def update
    if params[:cancel_login]
      client.request(:delete, "/login")
    else
      data = params.require(:connection).permit(:model, :background_paused, :enabled)
      models = client.request(:get, "/models").fetch("data")
      model = data[:model].presence
      raise Provider::Codex::Error, "Unavailable model" if model && models.none? { |m| m["id"] == model }
      connected = client.request(:get, "/account").dig("account", "type") == "chatgpt"
      raise Provider::Codex::Error, "Connect ChatGPT first" unless connected
      paused = ActiveModel::Type::Boolean.new.cast(data[:background_paused])
      client.request(:post, "/settings", { paused: paused })
      Setting.codex_model = model
      Setting.codex_background_paused = paused
      Setting.llm_provider = "codex" if data[:enabled] == "1"
      CodexDeferredJob.resume_ready unless paused
    end
    redirect_to settings_codex_connection_path, notice: t(".saved")
  rescue Provider::Codex::Error
    redirect_to settings_codex_connection_path, alert: t(".failed")
  end

  def destroy
    client.request(:delete, "/account")
    Setting.codex_background_paused = true
    # Retain selection so disconnect cannot activate a billed provider.
    redirect_to settings_codex_connection_path, notice: t(".disconnected")
  rescue Provider::Codex::Error
    redirect_to settings_codex_connection_path, alert: t(".failed")
  end

  private
    def client = @client ||= Provider::Codex::Client.new

    def ensure_owner
      head :forbidden unless Provider::Codex.available_for?(Current.user) && Current.user.admin?
    end
end
