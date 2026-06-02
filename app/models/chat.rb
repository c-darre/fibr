class Chat < ApplicationRecord
  belongs_to :analysis
  has_many :messages, dependent: :destroy
end
