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

  def self.resume_ready
    return unless Provider::Codex.selected? && !Setting.codex_background_paused
    where("resume_at IS NULL OR resume_at <= ?", Time.current).find_each do |record|
      transaction do
        record = lock.find_by(id: record.id)
        next unless record
        # Keep the durable claim until the queue acknowledges the job. A crash
        # can redeliver, so generation IDs and financial writes remain idempotent.
        job = ActiveJob::Base.deserialize(JSON.parse(record.serialized_job))
        job.class.queue_adapter.enqueue(job)
        record.destroy!
      end
    end
  end
end
