class Message < ApplicationRecord
  belongs_to :chat

  has_many_attached :photos

  enum :role, { user: 0, assistant: 1 }, default: :user

  after_create_commit -> {
    broadcast_append_to "chat_#{chat_id}",
      target: "messages-container",
      partial: "messages/message",
      locals: { message: self }
  }, if: -> { chat.kind == "questionnary" }
end
