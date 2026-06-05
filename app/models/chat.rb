class Chat < ApplicationRecord
  belongs_to :analysis
  has_many :messages, dependent: :destroy

  enum :kind, { analysis: 0, discussion: 1, photo_review: 2, questionnary: 3 }
end
