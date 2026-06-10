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

  after_create_commit -> {
    broadcast_append_to chat,
      target: "messages-container",
      partial: "messages/discussion_message",
      locals: { message: self }

    if role == "user"
      broadcast_append_to chat,
        target: "messages-container",
        html: '<div id="typing-indicator" class="quiz-msg quiz-msg--assistant"><div class="quiz-bubble quiz-typing">Expert is typing…</div></div>'
    end

    if role == "assistant"
      broadcast_remove_to chat, target: "typing-indicator"
    end
  }, if: -> { chat.kind == "discussion" }
end
