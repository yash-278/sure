class CreateCodexDeferredJobs < ActiveRecord::Migration[7.2]
  def change
    create_table :codex_deferred_jobs, id: :uuid do |t|
      t.string :job_id, null: false
      t.text :serialized_job, null: false
      t.string :reason, null: false
      t.datetime :resume_at
      t.timestamps
    end
    add_index :codex_deferred_jobs, :job_id, unique: true
  end
end
