class Message < ApplicationRecord
  belongs_to :chat

  has_many_attached :photos

  enum :role, { user: 0, assistant: 1 }, default: :user
end
