# Keeps paused jobs out of Sidekiq's failure loop. Arguments are existing
# ActiveJob record references; encryption also protects future argument changes.
class CodexDeferredJob < ApplicationRecord
  encrypts :serialized_job

  def self.store(job, error)
    record = create_or_find_by!(job_id: job.job_id) do |pending|
      pending.serialized_job = job.serialize.to_json
      pending.reason = error.failure_code.to_s
      pending.resume_at = error.resume_at
    end
    record.update!(reason: error.failure_code.to_s, resume_at: error.resume_at)
    CodexResumeJobsJob.set(wait_until: error.resume_at).perform_later if error.resume_at
  end

  def self.resume_ready(verified_connection: nil)
    return unless (Provider::Codex.selected? || Ai::Features.owner.present?) && !Setting.codex_background_paused
    return if Ai::Features.owner && !Ai::Features.owner.ai_enabled?
    where("resume_at IS NULL OR resume_at <= ?", Time.current).find_each do |record|
      transaction do
        record = lock.find_by(id: record.id)
        next unless record
        # Keep the durable claim until the queue acknowledges the job. A crash
        # can redeliver, so generation IDs and financial writes remain idempotent.
        job = ActiveJob::Base.deserialize(JSON.parse(record.serialized_job))
        if Ai::Features.owner
          features = Ai::Features.job_features(job)
          next if features.empty?
          configs = features.map { |feature| Ai::Features.new(Ai::Features.owner).configuration(feature) }
          next if configs.any?(&:blank?)
          # An API models listing cannot prove that a generation quota recovered.
          next if record.reason == "quota_exhausted" && configs.any? { |config| config["connection"] != "codex" && record.resume_at.nil? && verified_connection != config["connection"] }
          next unless configs.each_with_index.all? do |config, index|
            connection = Ai::Connection.new(config.fetch("connection"))
            next false unless connection.status[:state] == "connected"
            model = connection.models.find { |item| item["id"] == config["model"] }
            next false unless model
            begin
              Ai::Features.new(Ai::Features.owner).validate!(features[index], config, model)
              true
            rescue Provider::Error
              false
            end
          end
        end
        job.class.queue_adapter.enqueue(job)
        record.destroy!
      end
    rescue Provider::Error
      # Leave the durable job pending when a connection check cannot complete.
      next
    end
  end
end
