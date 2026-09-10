require "test_helper"

class CodexDeferredJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  test "pause stores one durable job without failing its rule run" do
    Setting.stubs(:llm_provider).returns("codex")
    Setting.stubs(:codex_background_paused).returns(true)
    job = AutoCategorizeJob.new(families(:dylan_family), transaction_ids: [])
    assert_difference "CodexDeferredJob.count", 1 do
      2.times { job.perform_now }
    end
    assert_equal "background_paused", CodexDeferredJob.find_by!(job_id: job.job_id).reason
  end

  test "resume retains the job ID and removes the claim after enqueue" do
    Setting.stubs(:llm_provider).returns("codex")
    Setting.stubs(:codex_background_paused).returns(false)
    job = AutoCategorizeJob.new(families(:dylan_family), transaction_ids: [])
    CodexDeferredJob.store(job, Provider::Codex::Deferred.new(:not_connected))
    assert_enqueued_with(job: AutoCategorizeJob) { CodexDeferredJob.resume_ready }
    assert_not CodexDeferredJob.exists?(job_id: job.job_id)
  end
end
