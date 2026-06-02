class Analysis < ApplicationRecord
  belongs_to :user, optional: true

  has_one :chat, dependent: :destroy
  has_many :criteria, class_name: "Criterium", dependent: :destroy

  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }, default: :pending
end
