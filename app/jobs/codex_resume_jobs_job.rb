class CodexResumeJobsJob < ApplicationJob
  def perform
    CodexDeferredJob.resume_ready
  end
end
