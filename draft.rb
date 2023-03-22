class Draft < Sequel::Model(:drafts)
  many_to_one :email
end
