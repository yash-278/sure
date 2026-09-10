class CreateCodexToolApprovals < ActiveRecord::Migration[7.2]
  def change
    create_table :codex_tool_approvals, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :chat, type: :uuid, null: false, foreign_key: true
      t.string :function_name, null: false
      t.text :arguments_json, null: false
      t.string :digest, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :result
      t.timestamps
    end
    add_index :codex_tool_approvals, [ :chat_id, :digest ], unique: true
  end
end
