Sequel.migration do
  up do
    create_table(:emails) do
      primary_key :id
      String :thread_id
      String :gmail_id
      Text :snippet
      Text :body
      String :subject
      String :from
      String :to
      String :cc
      String :bcc
      DateTime :date
      DateTime :created_at
      DateTime :updated_at
    end
  end

  down do
    drop_table(:emails)
  end
end
