class Analysis < ApplicationRecord
  belongs_to :user, optional: true

  has_many :chats, dependent: :destroy
  has_one :analysis_chat,     -> { where(kind: :analysis)      }, class_name: "Chat"
  has_one :discussion_chat,   -> { where(kind: :discussion)    }, class_name: "Chat"
  has_one :photo_review_chat, -> { where(kind: :photo_review)  }, class_name: "Chat"
  has_one :questionnary_chat, -> { where(kind: :questionnary)  }, class_name: "Chat"
  has_many :criteria, class_name: "Criterium", dependent: :destroy

  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }, default: :pending
end
