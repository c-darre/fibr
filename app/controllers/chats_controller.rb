class ChatsController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    @chat = Chat.find(params[:id])
    @analysis = @chat.analysis
    @message = Message.new
    @messages = @chat.messages.where.not(content: [nil, ""]).order(:created_at)
  end
end
