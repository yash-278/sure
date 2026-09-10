module CodexBackgroundWork
  extend ActiveSupport::Concern

  included do
    around_perform do |job, block|
      record = job.arguments.first
      family = record.is_a?(Family) ? record : record.respond_to?(:family) ? record.family : nil
      managed = Ai::Features.managed?(family)
      features = managed ? Ai::Features.new(Ai::Features.owner) : nil
      unconfigured = managed && Ai::Features.job_features(job).any? { |feature| features.configuration(feature).blank? }
      reason = if managed && !Ai::Features.owner.ai_enabled?
        :consent_required
      elsif unconfigured
        :feature_unconfigured
      elsif (Provider::Codex.selected? || managed) && Setting.codex_background_paused
        :background_paused
      end
      if reason
        CodexDeferredJob.store(job, Provider::Codex::Deferred.new(reason))
      else
        begin
          block.call
        rescue Provider::Codex::Deferred => error
          CodexDeferredJob.store(job, error)
        end
      end
    end
  end
end
