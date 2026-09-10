class CodexToolApprovalsController < ApplicationController
  before_action :require_preview_features!
  before_action :set_approval

  def show
  end

  def update
    if params[:decision] == "approve"
      @approval.approve!
    elsif params[:decision] == "reject"
      @approval.with_lock { @approval.update!(status: "rejected") if @approval.status == "pending" }
    else
      return head :unprocessable_entity
    end
    redirect_to chat_path(@approval.chat), notice: t(".saved")
  end

  private
    def set_approval
      return head :forbidden unless Provider::Codex.available_for?(Current.user)
      @approval = CodexToolApproval.where(user: Current.user).find(params[:id])
    end
end
