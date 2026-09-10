module CodexBackgroundWork
  extend ActiveSupport::Concern

  included do
    around_perform do |job, block|
      if Provider::Codex.selected? && Setting.codex_background_paused
        CodexDeferredJob.store(job, Provider::Codex::Deferred.new(:background_paused))
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
