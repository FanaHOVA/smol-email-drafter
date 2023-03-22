Sequel.migration do
  up do
    create_table(:drafts) do
      primary_key :id
      foreign_key :email_id, :emails
      String :prompt, :null=>false
      Text :result
      DateTime :created_at
      DateTime :updated_at
    end
  end

  down do
    drop_table(:drafts)
  end
end
