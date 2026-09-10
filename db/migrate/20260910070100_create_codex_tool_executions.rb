class CreateCodexToolExecutions < ActiveRecord::Migration[7.2]
  def change
    create_table :codex_tool_executions, id: :uuid do |t|
      t.references :chat, type: :uuid, null: false, foreign_key: true
      t.string :request_key, null: false
      t.jsonb :result
      t.timestamps
    end
    add_index :codex_tool_executions, [ :chat_id, :request_key ], unique: true
  end
end
